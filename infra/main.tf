terraform {
  required_version = ">= 1.8.0" 

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" 
    }
  }
}

variable "db_password" {
  description = "The master password for the RDS databases"
  type        = string
  sensitive   = true # This hides it from Terraform terminal output!
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

# 2a. Security Group for Databases
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

# 2b. Security Group for EMR
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
  password             = var.db_password
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
  password             = var.db_password
  skip_final_snapshot  = true
  publicly_accessible  = true
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

# Give the EMR EC2 instances full access to S3
resource "aws_iam_role_policy_attachment" "emr_s3_access" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "emr_ec2_attach" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}
resource "aws_iam_instance_profile" "emr_ec2_profile" {
  name = "emr_ec2_profile_poc"
  role = aws_iam_role.emr_ec2_role.name
}

# ==========================================
# AWS Secrets Manager (Using your MANUAL Vault)
# ==========================================

# 1. Fetch the existing vault you made manually
data "aws_secretsmanager_secret" "db_password" {
  name = "db_password" # Must exactly match the name you typed in the AWS Console
}

# 2. Give EMR the "Key" to open your manual Vault
resource "aws_iam_policy" "emr_secrets_policy" {
  name        = "emr_secrets_policy_poc"
  description = "Allow EMR to read the database password from Secrets Manager"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "secretsmanager:GetSecretValue",
        Effect   = "Allow",
        Resource = data.aws_secretsmanager_secret.db_password.arn # <--- Uses the DATA block here
      }
    ]
  })
}

# 3. Attach the Key to the EMR EC2 Profile
resource "aws_iam_role_policy_attachment" "emr_secrets_attach" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = aws_iam_policy.emr_secrets_policy.arn
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

# --- IDs needed for your Airflow DAG ---
output "emr_subnet_id" {
  value = tolist(data.aws_subnets.default.ids)[0]
}

output "emr_security_group_id" {
  value = aws_security_group.emr_sg.id
}

output "emr_service_role_name" {
  value = aws_iam_role.emr_service_role.name
}

output "emr_ec2_profile_name" {
  value = aws_iam_instance_profile.emr_ec2_profile.name
}