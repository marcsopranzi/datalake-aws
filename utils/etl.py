import sys
import boto3
import yaml
import logging
import json
from botocore.exceptions import ClientError
from datetime import datetime
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit, md5

# ==========================================
# Configure Logging
# ==========================================
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ==========================================
# Helper Function: Fetch Secret
# ==========================================
def get_db_password():
    secret_name = "db_password"
    region_name = "eu-north-1"

    logger.info(f"Connecting to AWS Secrets Manager to fetch '{secret_name}'...")
    
    # Boto3 automatically uses the EMR cluster's IAM role!
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        logger.error(f"Failed to retrieve secret from AWS: {e}")
        raise e

    secret_string = get_secret_value_response['SecretString']
    
    # Parse the JSON and grab the value for the key 'db_password'
    secret_dict = json.loads(secret_string)
    return secret_dict['db_password']

# ==========================================
# Helper Function: Smart JDBC Reader
# ==========================================
def read_table_smartly(spark, source, table_name, partition_col="id"):
    logger.info(f"Preparing to read table: {table_name}")
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
        logger.info(f"Table stats retrieved: {total_rows} rows. ID range: {min_id} to {max_id}")
    except Exception as e:
        logger.warning(f"Could not fetch stats for {table_name}. Falling back to single partition. Error: {e}")
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
        logger.info(f"{table_name} is BIG. Reading in parallel with {num_partitions} partitions.")
        reader = reader.option("partitionColumn", partition_col) \
            .option("lowerBound", str(min_id)) \
            .option("upperBound", str(max_id)) \
            .option("numPartitions", str(num_partitions))
    else:
        logger.info(f"{table_name} is SMALL. Reading in a single chunk.")

    return reader.load()

# ==========================================
# Main Execution
# ==========================================
if __name__ == "__main__":
    try:
        logger.info("Starting PySpark ETL Job...")
        
        # We now only expect ONE argument: the source name
        if len(sys.argv) < 2:
            logger.error("Usage: spark-submit s3://data-lake-ms/utils/etl.py <source_name>")
            sys.exit(1)

        target_source = sys.argv[1]
        bucket_name = 'data-lake-ms'

        logger.info(f"Target Source: {target_source}")

        # 1. Fetch Password from AWS Secrets Manager
        db_password = get_db_password()

        # 2. Fetch Config from S3
        logger.info("Fetching configuration from S3...")
        s3_client = boto3.client('s3')
        response = s3_client.get_object(Bucket=bucket_name, Key='utils/config.yaml')
        config_raw = response['Body'].read().decode('utf-8')

        # Replace password placeholders with the fetched secret
        config_raw = config_raw.replace("${DB_PASS_POSTGRES}", db_password)
        config_raw = config_raw.replace("${DB_PASS_MYSQL}", db_password)
        
        config = yaml.safe_load(config_raw)

        # 3. Start Spark
        logger.info("Initializing Spark Session...")
        spark = SparkSession.builder.appName(f"Ingestion_{target_source}").getOrCreate()

        source = next((s for s in config["sources"] if s["name"] == target_source), None)
        if not source:
            raise ValueError(f"Source '{target_source}' not found in YAML configuration!")

        run_date = datetime.now().strftime("%Y-%m-%d")

        # 4. Process Tables
        for table_info in source["tables"]:
            table_name = table_info["name"]
            partition_col = table_info.get("partition_col", "id")
            
            logger.info(f"--- Processing Table: {table_name} ---")
            df = read_table_smartly(spark, source, table_name, partition_col)

            # Mask PII
            for c in table_info.get("pii_columns", []):
                if c in df.columns:
                    logger.info(f"Masking PII column: {c}")
                    df = df.withColumn(c, md5(col(c)))

            df = df.withColumn("run_date", lit(run_date))
            
            clean_table = table_name.replace(".", "_")
            
            output_path = f"s3://{bucket_name}/{target_source}/{clean_table}"
            
            logger.info(f"Writing data to {output_path}...")
            df.write.mode("overwrite").partitionBy("run_date").parquet(output_path)
            
            logger.info(f"Successfully finished processing {table_name}")

        logger.info(f"✅ ETL Job completed successfully for source: {target_source}")
        spark.stop()

    except Exception as e:
        logger.error("❌ FATAL ERROR in ETL Pipeline!", exc_info=True)
        sys.exit(1)