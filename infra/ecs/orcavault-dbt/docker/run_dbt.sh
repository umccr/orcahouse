#!/bin/bash

set -euo pipefail

uname -a

export AWS_DEFAULT_REGION=ap-southeast-2

if [ -n "${DBT_ENV_SECRET_HOST+1}" ]; then
  echo "Found DBT_ENV..."
else
  echo "Set DBT_ENV from Secret Manager..."

  SECRET_STRING=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --output json | jq -r '.SecretString')
  DB_USER=$(jq -rn "$SECRET_STRING | .username")
  DB_PASSWORD=$(jq -rn "$SECRET_STRING | .password")

  export DBT_ENV_SECRET_HOST=$DB_HOST
  export DBT_ENV_SECRET_USER=$DB_USER
  export DBT_ENV_SECRET_PASSWORD=$DB_PASSWORD
fi

dbt --version
dbt --log-format text --no-send-anonymous-usage-stats --no-use-colors --no-quiet debug --target prod
dbt --log-format text --no-send-anonymous-usage-stats --no-use-colors --no-quiet run --target prod

echo "dbt run completed successfully!"
