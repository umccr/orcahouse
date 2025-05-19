# AppSync GraphQL API

This project sets up a GraphQL endpoint using **AWS AppSync**.

Use the `lims` setup as a reference to create new endpoints based on other RDS data sources.

---

## Steps to Create a New AppSync GraphQL API

You can generate a GraphQL schema from an Aurora RDS database using [AppSync RDS Introspection](https://docs.aws.amazon.com/appsync/latest/devguide/rds-introspection.html). This process outputs a JSON representation of your schema in SDL format. A custom script is then used to enhance this schema with query functions that support basic filtering and sorting.

The script will:

- Read the introspection-generated GraphQL SDL (in JSON format).
- Add a `list` query function for the specified table.
- Generate argument types to support filtering and sorting.

> **Note:** This process currently supports only single-table models.

### 1. Duplicate the Existing Configuration

1. Copy the existing `lims` folder and rename it for your new API (e.g., `myapi`).
2. Update `rds-data-config.json` with the configuration details for your new RDS data source.

---

### 2. Generate the GraphQL Schema

Use the `generate_schema.py` script to enhance the introspected schema with list queries and argument types.

The AppSync introspection process produces a GraphQL SDL schema in JSON format (`schema-out-file`). The script reads this file and generates a new SDL schema (`graphql-out-file`) that includes:

- Basic `list<TableName>` queries
- Input types for filtering and sorting
- Support for scalar types: `AWSDate`, `Float`, `String`, and `Int`

#### Script Usage

```sh
usage: generate_schema.py [-h] [--introspection-id INTROSPECTION_ID] --model-name MODEL_NAME --config-file CONFIG_FILE --schema-out-file SCHEMA_OUT_FILE [-o GRAPHQL_OUT_FILE]

Generate GraphQL schema from JSON model using AWS AppSync introspection.

options:
  -h, --help            show this help message and exit
  --introspection-id INTROSPECTION_ID
                        If provided, skips starting introspection and uses this ID directly.
  --model-name MODEL_NAME
                        Name of the model to introspect (e.g., 'lims').
  --config-file CONFIG_FILE
                        Path to the RDS config file (e.g., ./rds-data-config.json).
  --schema-out-file SCHEMA_OUT_FILE
                        Where to save the downloaded model JSON (e.g., introspection-schema.json).
  -o, --graphql-out-file GRAPHQL_OUT_FILE
                        Where to write the GraphQL output schema.
```

Example (for lims API)

```sh
python3 generate_schema.py --model-name lims --config-file ./lims/rds-data-config.json --schema-out-file ./lims/introspection-schema.json -o ./lims/schema.graphql
```

### 3. Modify the Resolvers

Resolvers are located in the `./resolvers/` directory. For each resolver:

- Update the variable that specifies the target table.
- Adjust the resolver type and schema references to reflect your database structure.
- Look for the comment:  
  `# Modify the following code to match your database schema.`  
  and make changes accordingly.

---

### 4. Update Terraform Configuration

1. Open `main.tf`.
2. Update the relevant local variables and configurations to match your new API.

---

### 5. Deploy with Terraform

Run the following commands from the project root:

```sh
terraform init
terraform plan
terraform apply

```
