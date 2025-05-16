# AppSync GraphQL API

This project sets up a GraphQL endpoint using **AWS AppSync**.

Use the `lims` setup as a reference to create new endpoints based on other RDS data sources.

---

## Steps to Create a New AppSync GraphQL API

### 1. Duplicate the Existing Configuration

1. Copy the `lims` folder and rename it for your new API (e.g., `myapi`).
2. Update the contents of `rds-data-config.json` to match the configuration for the new data source.

---

### 2. Generate the GraphQL Schema

Use the `generate_schema.py` script to introspect the model and output a GraphQL SDL schema.

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
