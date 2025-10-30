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

legacy:
	@docker compose cp ./src/legacy.sql postgres:/tmp/legacy.sql
	@docker compose exec -e PGPASSWORD=dev -it postgres psql -h 0.0.0.0 -d orcavault -U dev -f /tmp/legacy.sql

ods:
	@docker compose cp ./src/ods.sql postgres:/tmp/ods.sql
	@docker compose exec -e PGPASSWORD=dev -it postgres psql -h 0.0.0.0 -d orcavault -U dev -f /tmp/ods.sql

tsa:
	@docker compose cp ./src/tsa.sql postgres:/tmp/tsa.sql
	@docker compose exec -e PGPASSWORD=dev -it postgres psql -h 0.0.0.0 -d orcavault -U dev -f /tmp/tsa.sql

psa:
	@docker compose cp ./src/psa.sql postgres:/tmp/psa.sql
	@docker compose exec -e PGPASSWORD=dev -it postgres psql -h 0.0.0.0 -d orcavault -U dev -f /tmp/psa.sql

all: legacy ods tsa psa

load:
	@docker compose cp ./src/load.sh postgres:/tmp/load.sh
	@docker compose exec -it postgres bash /tmp/load.sh

wait:
	@sleep 5

reload: down up wait all load next

next:
	@docker compose cp ./src/next.sh postgres:/tmp/next.sh
	@docker compose exec -it postgres bash /tmp/next.sh

sync:
	@rm -rf data/*.csv
	@aws s3 sync s3://orcabus-dev-backup-843407916570-ap-southeast-2/orcavault/data/ data/
