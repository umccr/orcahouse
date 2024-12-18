# Development

We expect the following dev tools be installed and available in your system PATH. We provide [Brewfile](Brewfile) as an example on macOS and you can run `brew bundle` to install them. You can manage these dev tools in any other way as see fit for your local dev setup and suits to your OS.

Tools:
- Docker Desktop (or equivalent)
- Python3 and prefer way to manage virtual environment
- Makefile _(Optional `make` binary to execute [Makefile](Makefile) targets. You can directly call those commands and scripts, otherwise.)_
- dbt-core CLI - https://github.com/dbt-labs/dbt-core

Example:

From project root directory, setup like so.
```
uv venv --python 3.13
source .venv/bin/activate
uv pip install -r dev/requirements.txt
```

Note that we use Python3 virtual environment (conda, uv, venv or any equivalent) for managing dbt-core CLI and other commandline tools (if any). No Python development nor syntax familiarity is expected. We are SQL shop! See next section.

## Skills

Dev:

- SQL (intermediate to advanced - CTE, CTAS, JOIN, WINDOW, PARTITION, RANK, ROW_NUMBER, CASE/WHEN, etc.)
- dbt
- PostgreSQL (data type, built-in functions, PL/pgSQL and stored procedure, view, trigger, etc.)
- Fundamental in database design and data modelling concepts 
  - relational data modelling / entity-relationship data modelling (ERD, 3NF, BCNF, FK, PK, UK, etc.)
- Data warehouse data modelling techniques
  - Data Vault 2.0 (Daniel Linstedt)
  - Dimensional Modelling (Ralph Kimball)


Infra:

- AWS (RDS Aurora, Redshift, Athena, Glue)
- Datalake (S3)
- Terraform
- Git and GitHub
- Database Administration - DBA (query pref, tuning, backup, snapshot, proxy, tunnel, etc.)
- DataBricks, BigQuery (optionally building data mart layer when applicable)


IDE:

_note; recommendation only. leverage any other IDE combo as see fit for your productivity._

- VSCode
- JetBrains (PyCharm, DataGrip)
- DBeaver
- pgAdmin
- Oracle SQL Developer
- https://github.com/dineug/erd-editor
