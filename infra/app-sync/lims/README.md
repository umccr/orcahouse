# Lims mart appsync

To generate the schema with the python script (`../transform_to_graphql.py`)

```sh

python3 transform_to_graphql.py --model-name lims --config-file ./lims/rds-data-config.json --schema-out-file ./introspection-schema.json -o new.graphql

```
