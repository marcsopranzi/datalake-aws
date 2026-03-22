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
	

# Initializes the Terraform directory inside the infra folder
init:
	terraform -chdir=infra init

# Builds your AWS infrastructure
apply:
	terraform -chdir=infra apply -auto-approve

# Deletes everything to save your credits
destroy:
	terraform -chdir=infra destroy -auto-approve

vars:
	terraform -chdir=infra output redshift_endpoint
	terraform -chdir=infra output postgres_endpoint


dbs:
	export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"
	export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

	mysql -h poc-mysql.cnkoswoqk901.eu-north-1.rds.amazonaws.com -P 3306 -u admin -p < utils/mysql_init.sql
	psql -h poc-postgres.cnkoswoqk901.eu-north-1.rds.amazonaws.com -U dbadmin -d postgres -f utils/postgres_init.sql