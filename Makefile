install:
	@pre-commit install
	@pre-commit autoupdate

check: install
	@pre-commit run --all-files

scan:
	@trufflehog --debug --only-verified git file://./ --since-commit main --branch HEAD --fail

deep: scan
	@ggshield secret scan repo .

baseline:
	@detect-secrets scan --exclude-files '^(.venv/|.local/|.terraform/|terraform.tfstate.d/|dbt_packages/|logs/)|package-lock.yml' > .secrets.baseline

test:
	@(cd orcavault && dbt deps && dbt test)

# The OrcaVault run's runner, see infra/ecs/orcavault-run/README.md. Needs uv,
# but neither dbt nor AWS. Fails if its uv.lock is out of date.
test-runner:
	@(cd infra/ecs/orcavault-run/docker/runner && uv run --locked pytest)

# NOTE: not suitable target for local running but specifically setup for anonymous CI runner  ~victor
test-iac:
	@(cd infra/ec2/umccr-mgmt && terraform init -backend=false && terraform fmt -check && terraform validate && terraform test)
	@(cd infra/ec2/warehouse-mgmt && terraform init -backend=false && terraform fmt -check && terraform validate && terraform test)
	@(cd infra/ecs/orcavault-run/modules/orcavault-run && terraform init -backend=false && terraform fmt -check && terraform validate && terraform test)
	@(cd infra/ecs/orcavault-run/account-wide && terraform init -backend=false && terraform fmt -check && terraform validate)
	@(cd infra/ecs/orcavault-run/environments/dev && terraform init -backend=false && terraform fmt -check && terraform validate)
	@(cd infra/ecs/orcavault-run/environments/prod && terraform init -backend=false && terraform fmt -check && terraform validate)
