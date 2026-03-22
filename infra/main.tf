terraform {
  required_version = ">= 1.8.0" 

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" 
    }
  }
}

provider "aws" {
  region = "eu-north-1" 
}

# 1. Get your Default Network 
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 2a. Security Group for Databases (Open specific ports to your Mac)
resource "aws_security_group" "db_sg" {
  name        = "datalake-db-sg"
  description = "Allow DB traffic from anywhere, and internal EMR traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Postgres
  }
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # MySQL
  }
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Redshift
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.default.cidr_block] # Internal VPC traffic
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2b. Security Group for EMR (Strictly Port 22 to satisfy AWS safety rules)
resource "aws_security_group" "emr_sg" {
  name        = "datalake-emr-sg"
  description = "Allow SSH from anywhere, and internal EMR traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.default.cidr_block] # Internal VPC traffic
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. MySQL Database
resource "aws_db_instance" "mysql_poc" {
  identifier           = "poc-mysql"
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t4g.micro"
  username             = "admin"
  password             = "supersecret123" 
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  publicly_accessible  = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
}

# 4. Postgres Database
resource "aws_db_instance" "postgres_poc" {
  identifier           = "poc-postgres"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "15"
  instance_class       = "db.t4g.micro"
  username             = "dbadmin"
  password             = "supersecret123"
  skip_final_snapshot  = true
  publicly_accessible  = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
}

# 5. Redshift Cluster (Upgraded to RA3)
resource "aws_redshift_cluster" "redshift_poc" {
  cluster_identifier  = "poc-redshift"
  database_name       = "datalake"
  master_username     = "dbadmin"         
  master_password     = "SuperSecret123!"
  node_type           = "ra3.xlplus"      # <--- The Redshift fix!
  cluster_type        = "single-node"
  skip_final_snapshot = true
  publicly_accessible = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
}

# 6. IAM Roles for EMR
resource "aws_iam_role" "emr_service_role" {
  name = "emr_service_role_poc"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "elasticmapreduce.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "emr_service_attach" {
  role       = aws_iam_role.emr_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

resource "aws_iam_role" "emr_ec2_role" {
  name = "emr_ec2_role_poc"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "emr_ec2_attach" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}
resource "aws_iam_instance_profile" "emr_ec2_profile" {
  name = "emr_ec2_profile_poc"
  role = aws_iam_role.emr_ec2_role.name
}

# 7. EMR Cluster
resource "aws_emr_cluster" "cluster" {
  name          = "poc-datalake-spark"
  release_label = "emr-6.15.0"
  applications  = ["Spark", "Hadoop"]
  service_role  = aws_iam_role.emr_service_role.arn

  ec2_attributes {
    subnet_id                         = tolist(data.aws_subnets.default.ids)[0]
    emr_managed_master_security_group = aws_security_group.emr_sg.id  # <--- The EMR fix!
    emr_managed_slave_security_group  = aws_security_group.emr_sg.id
    instance_profile                  = aws_iam_instance_profile.emr_ec2_profile.arn
  }

  master_instance_group {
    instance_type  = "m5.xlarge"
    instance_count = 1
  }

  core_instance_group {
    instance_type  = "m5.xlarge"
    instance_count = 1
  }
}

# ==========================================
# Outputs 
# ==========================================
output "mysql_endpoint" {
  value = aws_db_instance.mysql_poc.endpoint
}

output "postgres_endpoint" {
  value = aws_db_instance.postgres_poc.endpoint
}

output "redshift_endpoint" {
  value = aws_redshift_cluster.redshift_poc.endpoint
}

output "emr_master_dns" {
  value = aws_emr_cluster.cluster.master_public_dns
}