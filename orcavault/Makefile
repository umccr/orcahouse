# convenience shortcuts to dev/Makefile targets

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

load:
	@(cd ../dev/ && $(MAKE) load)

reload: down up ods load

sync:
	@(cd ../dev/ && $(MAKE) sync)
