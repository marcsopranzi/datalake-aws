import sys
import os
import yaml
import boto3
from datetime import datetime
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit, md5

# ==========================================
# Helper Function: Smart JDBC Reader
# ==========================================
def read_table_smartly(spark, source, table_name, partition_col="id"):
    stats_query = f"(SELECT COUNT(*) as total_rows, MIN({partition_col}) as min_id, MAX({partition_col}) as max_id FROM {table_name}) AS stats"
    
    try:
        stats_df = spark.read.format("jdbc") \
            .option("url", source["url"]) \
            .option("dbtable", stats_query) \
            .option("driver", source["driver"]) \
            .option("user", source.get("user", "")) \
            .option("password", source.get("password", "")) \
            .load()
        
        stats = stats_df.collect()[0]
        total_rows = stats["total_rows"]
        min_id = stats["min_id"]
        max_id = stats["max_id"]
    except Exception as e:
        print(f"  -> Could not fetch stats for {table_name}. Falling back to single partition. Error: {e}")
        total_rows = 0
        min_id, max_id = None, None

    reader = spark.read.format("jdbc") \
        .option("url", source["url"]) \
        .option("dbtable", table_name) \
        .option("driver", source["driver"]) \
        .option("user", source.get("user", "")) \
        .option("password", source.get("password", ""))
    
    if total_rows > 1000000 and min_id is not None and max_id is not None:
        num_partitions = min(50, max(10, total_rows // 500000))
        print(f"  -> {table_name} is BIG ({total_rows} rows). Reading in parallel with {num_partitions} partitions.")
        reader = reader.option("partitionColumn", partition_col) \
            .option("lowerBound", str(min_id)) \
            .option("upperBound", str(max_id)) \
            .option("numPartitions", str(num_partitions))
    else:
        print(f"  -> {table_name} is SMALL ({total_rows} rows). Reading in a single chunk.")

    return reader.load()

# ==========================================
# Main Execution
# ==========================================
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: spark-submit s3://your-bucket/scripts/etl.py <source_name>")
        sys.exit(1)

    target_source = sys.argv[1]

    # 1. Boto3 automatically uses the EMR cluster's IAM Role!
    s3_client = boto3.client('s3')

    # 2. Read Config directly from S3
    # Make sure to update 'your-bucket-name'
    response = s3_client.get_object(Bucket='your-bucket-name', Key='utils/config.yaml')
    config_raw = response['Body'].read().decode('utf-8')

    for env_var in ["DB_USER_POSTGRES", "DB_PASS_POSTGRES", "DB_USER_MYSQL", "DB_PASS_MYSQL"]:
        val = os.getenv(env_var, "")
        config_raw = config_raw.replace(f"${{{env_var}}}", val)

    config = yaml.safe_load(config_raw)

    # 3. Start Spark (EMR comes pre-configured for S3)
    spark = SparkSession.builder.appName(f"Ingestion_{target_source}").getOrCreate()

    source = next((s for s in config["sources"] if s["name"] == target_source), None)
    if not source:
        print(f"Source '{target_source}' not found in YAML!")
        sys.exit(1)

    run_date = datetime.now().strftime("%Y-%m-%d")

    for table_info in source["tables"]:
        table_name = table_info["name"]
        partition_col = table_info.get("partition_col", "id")
        
        print(f"Ingesting {table_name}...")
        df = read_table_smartly(spark, source, table_name, partition_col)

        for c in table_info.get("pii_columns", []):
            if c in df.columns:
                df = df.withColumn(c, md5(col(c)))

        df = df.withColumn("run_date", lit(run_date))
        
        clean_table = table_name.replace(".", "_")
        
        # 4. Use s3:// instead of s3a:// for EMRFS optimization
        output_path = f"s3://{config['s3']['bucket']}/{target_source}/{clean_table}"
        
        df.write.mode("overwrite").partitionBy("run_date").parquet(output_path)
        print(f"Finished {table_name}")

    print(f"Done ingesting all tables for {target_source}")
    spark.stop()