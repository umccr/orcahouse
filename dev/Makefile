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
	@docker compose logs postgres -f

ls:
	@docker compose exec -it postgres ls -l $(dd)

psql:
	@docker compose exec -e PGPASSWORD=dev -it postgres psql -h 0.0.0.0 -d orcavault -U dev

ods:
	@docker compose cp ./src/ods.sql postgres:/tmp/ods.sql
	@docker compose exec -e PGPASSWORD=dev -it postgres psql -h 0.0.0.0 -d orcavault -U dev -f /tmp/ods.sql

tsa:
	@docker compose cp ./src/tsa.sql postgres:/tmp/tsa.sql
	@docker compose exec -e PGPASSWORD=dev -it postgres psql -h 0.0.0.0 -d orcavault -U dev -f /tmp/tsa.sql

all: ods tsa

load:
	@docker compose cp ./src/load.sh postgres:/tmp/load.sh
	@docker compose exec -it postgres bash /tmp/load.sh

sync:
	@aws s3 sync s3://orcabus-test-data-843407916570-ap-southeast-2/orcavault/data/ data/
