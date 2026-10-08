# Usage:
# 	make ls
# 	make ls dd=/tmp
dd ?= /

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

deps:
	@docker compose exec -it glue bash -c "python3 -m pip install -r requirements.txt"

glue: deps
	@docker compose exec -it glue bash

restart: down up glue

spark:
	@docker compose exec -it glue bash -c "~/spark/bin/pyspark --version"

pyspark:
	@docker compose exec -it glue bash -c "~/spark/bin/pyspark"

sample:
	@docker compose exec -it glue bash -c "~/spark/bin/spark-submit jupyter_workspace/skel/sample.py"
