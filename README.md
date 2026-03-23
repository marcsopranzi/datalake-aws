# datalake-aws
Data Lake Ingestion Setup

This project uses Airflow to orchestrate PySpark jobs on transient EMR clusters.
1. Prerequisites

You need these tools installed on your local machine:

    Docker & Docker Compose: To run the Airflow environment.

    AWS CLI: To manage your cloud resources and sync files.

    Make: To run the automation shortcuts in the Makefile.

2. Environment Variables

Before running anything, export these to your terminal (or add them to your .zshrc or .bashrc):
Bash

export AWS_ACCESS_KEY_ID="your_key"
export AWS_SECRET_ACCESS_KEY="your_secret"
export AWS_DEFAULT_REGION="eu-north-1"
export DB_PASSWORD="your_database_password"

3. Cloud Infrastructure

    S3 Bucket: Create a bucket named data-lake-ms.

    Subnet & Security Groups: Ensure you have a private subnet and a security group that allows traffic between EMR and your RDS instance.

    Secrets Manager: Create a secret for your database password so the ETL script can fetch it securely.

4. Makefile Commands

Use these shortcuts to manage the pipeline:

    make sync: Uploads your etl.py, config.yaml, and bootstrap.sh to S3.

    make set-aws-conn: Automatically updates the AWS connection inside the Airflow container.

5. Running the Pipeline

    Start Airflow with docker-compose up.

    Run make set-aws-conn.

    Run make sync.

    Trigger the DAG in the Airflow UI.