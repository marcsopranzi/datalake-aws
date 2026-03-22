import logging
from airflow import DAG
from datetime import datetime
from airflow.providers.amazon.aws.operators.emr import EmrCreateJobFlowOperator
from airflow.providers.amazon.aws.sensors.emr import EmrJobFlowSensor
from airflow.operators.python import PythonOperator

# 1. Custom Logging Functions
def log_start():
    logging.info("🚀 STARTING: Firing up the transient EMR cluster for MySQL Ingestion...")

def log_finish():
    logging.info("✅ SUCCESS: EMR job finished perfectly and the cluster has been terminated!")

# 2. Your EMR Configuration
JOB_FLOW_OVERRIDES = {
    "Name": "Airflow-Transient-MySQL-Ingestion",
    "ReleaseLabel": "emr-6.15.0",
    "LogUri": "s3://data-lake-ms/logs/",
    "Instances": {
        "InstanceGroups": [
            {"Name": "Master node", "Market": "ON_DEMAND", "InstanceRole": "MASTER", "InstanceType": "m5.xlarge", "InstanceCount": 1},
            {"Name": "Core node", "Market": "ON_DEMAND", "InstanceRole": "CORE", "InstanceType": "m5.xlarge", "InstanceCount": 1}
        ],
        "KeepJobFlowAliveWhenNoSteps": False, 
        "Ec2SubnetId": "subnet-09e4f6118a906642b",     
        "EmrManagedMasterSecurityGroup": "sg-0ea61c088268cf9ea", 
        "EmrManagedSlaveSecurityGroup": "sg-0ea61c088268cf9ea"   
    },
    "JobFlowRole": "emr_ec2_profile_poc",     
    "ServiceRole": "emr_service_role_poc",    
    "Steps": [
        {
            "Name": "Run PySpark Ingestion",
            "ActionOnFailure": "TERMINATE_CLUSTER",
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "spark-submit",
                    "--deploy-mode", "cluster",
                    "--packages", "org.postgresql:postgresql:42.6.0,mysql:mysql-connector-java:8.0.33",
                    "s3://data-lake-ms/utils/etl.py",
                    "mysql_db"  
                ]
            }
        }
    ]
}

# 3. The DAG Workflow
with DAG(
    dag_id="emr_ingestion_workflow",
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False
) as dag:

    # Task A: Log the start
    start_logging = PythonOperator(
        task_id="log_start",
        python_callable=log_start
    )

    # Task B: Send the launch command to AWS
    create_emr_cluster = EmrCreateJobFlowOperator(
        task_id="create_emr_cluster",
        job_flow_overrides=JOB_FLOW_OVERRIDES,
        aws_conn_id="aws_default",
    )

    # Task C: Wait patiently for the cluster to finish its work and terminate
    # (It gets the Job Flow ID dynamically from Task B)
    wait_for_cluster = EmrJobFlowSensor(
        task_id="wait_for_cluster",
        job_flow_id="{{ task_instance.xcom_pull(task_ids='create_emr_cluster', key='return_value') }}",
        aws_conn_id="aws_default",
    )

    # Task D: Log the successful finish
    finish_logging = PythonOperator(
        task_id="log_finish",
        python_callable=log_finish
    )

    # 4. Set the exact order they should run
    start_logging >> create_emr_cluster >> wait_for_cluster >> finish_logging