.PHONY: install init apply destroy



# Installs tfenv, then installs and locks a specific Terraform version
install:
	brew install libpq
	brew link --force libpq
	brew install mysql-client
	brew install tfenv
	tfenv install 1.8.0
	tfenv use 1.8.0
	terraform -version
	mkdir -phi logs plugins
	
# Initializes the Terraform directory inside the infra folder
init:
	terraform -chdir=infra init
	
# Builds your AWS infrastructure
# Builds your AWS infrastructure
apply:
	terraform -chdir=infra apply -var="db_password=$(DB_PASSWORD)" -auto-approve
    
# Deletes everything to save your credits
destroy:
	terraform -chdir=infra destroy -var="db_password=$(DB_PASSWORD)" -auto-approve

vars:
	@MYSQL_HOST=$$(terraform -chdir=infra output -raw mysql_endpoint | cut -d: -f1); \
	POSTGRES_HOST=$$(terraform -chdir=infra output -raw postgres_endpoint | cut -d: -f1); \
	echo "MySQL Host: $$MYSQL_HOST"; \
	echo "Postgres Host: $$POSTGRES_HOST"

# This actually runs the init scripts
dbs: vars
		@echo "Fetching endpoints and initializing databases..."
		@MYSQL_HOST=$$(terraform -chdir=infra output -raw mysql_endpoint | cut -d: -f1); \
		POSTGRES_HOST=$$(terraform -chdir=infra output -raw postgres_endpoint | cut -d: -f1); \
		mysql -h $$MYSQL_HOST -P 3306 -u admin -p"$(DB_PASSWORD)" < utils/mysql_init.sql; \
		PGPASSWORD="$(DB_PASSWORD)" psql -h $$POSTGRES_HOST -U dbadmin -d postgres -f utils/postgres_init.sql

sync:
	@echo "Uploading utils/ folder to S3..."
	aws s3 sync utils/ s3://data-lake-ms/utils/
	@echo "✅ Upload complete!"

# Update Airflow AWS Connection
# Usage: make set-aws-conn
set-aws-conn:
	@echo "Deleting old connection if it exists..."
	docker exec -t datalake-aws-airflow-webserver-1 airflow connections delete aws_default || true
	@echo "Creating new aws_default connection..."
	docker exec -t datalake-aws-airflow-webserver-1 airflow connections add aws_default \
		--conn-type 'aws' \
		--conn-login '$(AWS_ACCESS_KEY_ID)' \
		--conn-password '$(AWS_SECRET_ACCESS_KEY)' \
		--conn-extra '{"region_name": "eu-north-1"}'