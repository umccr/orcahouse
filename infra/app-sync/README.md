# AppSync GraphQL API Setup Guide

This guide explains how to create a new AppSync GraphQL API by cloning an existing configuration, downloading and transforming the schema, and applying the Terraform setup.

---

## Steps to Create a New AppSync GraphQL API

### 1. Clone the Existing API Configuration

1. Navigate to the `apis/` directory:

    ```sh
    cd apis/
    ```

2. Clone the metadata folder to create a new subfolder for your API:

    ```sh
    cp -r metadata <new_api_name>
    ```

Replace `<new_api_name>` with the desired name of your new API.

---


### 2. Configure the configuration

In the ./rds-data-config.json reconfigure so it is suitable for the databse where it will connect.


---


### 2. Download the Schema

Run the `download_schema.sh` script to fetch the schema for your new API.

Replace the placeholders with your specific values:

- `<model_name>` — name of your model (e.g., `app_user`)
- `<new_api_name>` — name of your new API

```sh
./download_schema.sh some_model_name ./apis/{REPLACE_API_NAME}/rds-data-config.json ./apis/{REPLACE_API_NAME}/introspection-schema.json

```

---

### 3. Transform the Schema

Use the `transform_to_graphql.py` script to convert the introspection schema to a standard GraphQL schema:

```sh
python3 transform_to_graphql.py ./apis/{REPLACE_API_NAME}/introspection-schema.json ./apis/{REPLACE_API_NAME}/schema.graphql
```

---


### 3. Modify resolvers

The function in the ./resolvers has the variable to idenift which table it should query from. modify appropriately

---

### 4. Update the Terraform Configuration

1. Open the `main.tf` file located in `apis/<new_api_name>/`.

2. Update the local configuration with details specific to your new API:
   - Change `api_name`, resolvers, and any relevant variables.
   - Ensure the `schema.graphql` file path is correct.

---

### 5. Apply the Terraform Configuration

Run the following commands:

```sh
terraform init
terraform plan
terraform apply
```
