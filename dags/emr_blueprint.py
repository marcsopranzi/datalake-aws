def get_emr_config(source_name):
    """
    Returns the full EMR configuration dictionary.
    Includes the bootstrap script we fixed and the specific database source.
    """
    return {
        "Name": f"Airflow-Transient-{source_name.replace('_', '-').capitalize()}",
        "ReleaseLabel": "emr-6.15.0",
        "LogUri": "s3://data-lake-ms/logs/",
        "BootstrapActions": [
            {
                "Name": "Install Python Dependencies",
                "ScriptBootstrapAction": {
                    "Path": "s3://data-lake-ms/utils/bootstrap.sh"
                }
            }
        ],
        "Instances": {
            "InstanceGroups": [
                {"Name": "Master node", "Market": "ON_DEMAND", "InstanceRole": "MASTER", "InstanceType": "m5.xlarge", "InstanceCount": 1},
                {"Name": "Core node", "Market": "ON_DEMAND", "InstanceRole": "CORE", "InstanceType": "m5.xlarge", "InstanceCount": 1}
            ],
            "KeepJobFlowAliveWhenNoSteps": False, 
            "Ec2SubnetId": "subnet-09e4f6118a906642b",     
            "EmrManagedMasterSecurityGroup": "sg-0e94a00b1082babc3", 
            "EmrManagedSlaveSecurityGroup": "sg-0e94a00b1082babc3"   
        },
        "JobFlowRole": "emr_ec2_profile_poc",     
        "ServiceRole": "emr_service_role_poc",    
        "Steps": [
            {
                "Name": f"Run PySpark Ingestion - {source_name}",
                "ActionOnFailure": "TERMINATE_CLUSTER",
                "HadoopJarStep": {
                    "Jar": "command-runner.jar",
                    "Args": [
                        "spark-submit",
                        "--deploy-mode", "cluster",
                        "--packages", "org.postgresql:postgresql:42.6.0,mysql:mysql-connector-java:8.0.33",
                        "s3://data-lake-ms/utils/etl.py",
                        source_name 
                    ]
                }
            }
        ]
    }