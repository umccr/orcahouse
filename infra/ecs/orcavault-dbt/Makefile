.PHONY: build

build:
	@(cd docker && bash build.sh)

run:
	@docker run --rm --platform linux/arm64 \
		-e DBT_ENV_SECRET_HOST=host.docker.internal \
		-e DBT_ENV_SECRET_USER=dev \
		-e DBT_ENV_SECRET_PASSWORD=dev \
		orcavault-dbt

rune:
	@docker run --rm --platform linux/arm64 orcavault-dbt

runit:
	@docker run -it --rm --entrypoint bash --platform linux/arm64 orcavault-dbt

test: run

list:
	@terraform workspace list

plan:
	@export AWS_PROFILE=umccr-prod-admin && terraform workspace select prod && terraform plan

apply:
	@terraform apply

invoke:
	@aws ecs run-task \
  		--cluster orcahouse-orcavault-dbt \
		--task-definition orcahouse-orcavault-dbt \
		--count 1 \
		--launch-type FARGATE \
		--network-configuration "awsvpcConfiguration={subnets=[\"subnet-01ae2b4ad1eb584d7\", \"subnet-01be4c1109eca3446\", \"subnet-070a9acba78168239\"],securityGroups=[\"sg-013b6e66086adc6a6\"],assignPublicIp=\"DISABLED\"}"

logs:
	@aws logs tail /aws/ecs/orcahouse-orcavault-dbt --follow
