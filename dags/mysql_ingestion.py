from airflow import DAG
from datetime import datetime
from airflow.providers.amazon.aws.operators.emr import EmrCreateJobFlowOperator
from airflow.providers.amazon.aws.sensors.emr import EmrJobFlowSensor
from emr_blueprint import get_emr_config

with DAG(
    dag_id="mysql_ingestion_workflow",
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 3 * * *", # 3 AM daily
    catchup=False
) as dag:

    create_cluster = EmrCreateJobFlowOperator(
        task_id="create_emr_cluster",
        job_flow_overrides=get_emr_config("mysql_source"),
        aws_conn_id="aws_default"
    )

    wait_for_cluster = EmrJobFlowSensor(
        task_id="wait_for_cluster",
        job_flow_id="{{ task_instance.xcom_pull(task_ids='create_emr_cluster', key='return_value') }}",
        aws_conn_id="aws_default"
    )

    create_cluster >> wait_for_cluster