# Usage:
# 	make ls
# 	make ls dd=/tmp
dd ?= /

aws:
	@env | grep AWS_

# If you are using granted.dev, you can instead `assume -r umccr-dev-admin`
aws-env:
	@echo Using $$AWS_PROFILE
	@aws configure export-credentials --profile $$AWS_PROFILE --format env > .env
	@. .env

up:
	@docker compose up --wait -d

down:
	@docker compose down

stop: down

ps:
	@docker compose ps

tail:
	@docker compose logs glue -f

ls:
	@docker compose exec -it glue ls -l $(dd)

pwd:
	@docker compose exec -it glue pwd

glue:
	@docker compose exec -it glue bash

spark:
	@docker compose exec -it glue bash -c "~/spark/bin/pyspark --version"

pyspark:
	@docker compose exec -it glue bash -c "~/spark/bin/pyspark"

sample:
	@docker compose exec -it glue bash -c "~/spark/bin/spark-submit jupyter_workspace/skel/sample.py"
