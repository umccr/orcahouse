# convenience shortcuts to dev/Makefile targets

doc:
	@dbt docs generate
	@rm -rf .local/orcavault
	@mkdir -p .local/orcavault
	@cp -v target/*.json .local/orcavault/
	@cp -v target/*.html .local/orcavault/

up:
	@(cd ../dev/ && $(MAKE) up)

down:
	@(cd ../dev/ && $(MAKE) down)

stop: down

ps:
	@(cd ../dev/ && $(MAKE) ps)

tail:
	@(cd ../dev/ && $(MAKE) tail)

ls:
	@(cd ../dev/ && $(MAKE) ls)

psql:
	@(cd ../dev/ && $(MAKE) psql)

ods:
	@(cd ../dev/ && $(MAKE) ods)

tsa:
	@(cd ../dev/ && $(MAKE) tsa)

psa:
	@(cd ../dev/ && $(MAKE) psa)

all:
	@(cd ../dev/ && $(MAKE) all)

load:
	@(cd ../dev/ && $(MAKE) load)

reload:
	@(cd ../dev/ && $(MAKE) reload)

next:
	@(cd ../dev/ && $(MAKE) next)

sync:
	@(cd ../dev/ && $(MAKE) sync)
