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

# NOTE: not suitable target for local running but specifically setup for anonymous CI runner  ~victor
test-iac:
	@(cd infra/ec2 && terraform init -backend=false && terraform fmt -check && terraform validate && terraform test)
