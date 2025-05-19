# LIMS Mart AppSync

This project generates a GraphQL schema for the `lims` table in the OrcaHouse Vault database using AWS AppSync and RDS introspection.

## Generate the GraphQL Schema

Run the provided Python script (../generate_schema.py) to convert the RDS introspection JSON into a GraphQL SDL schema. Make sure to run the command from the same directory as the script.

```sh
python3 generate_schema.py \
  --model-name lims \
  --config-file ./lims/rds-data-config.json \
  --schema-out-file ./lims/introspection-schema.json \
  -o ./lims/schema.graphql
```
