import argparse
import json
import subprocess
import time
from pathlib import Path
from textwrap import indent
from typing import Dict, List, Optional

# --------------------------
# Utilities
# --------------------------


def to_pascal_case(s):
    return ''.join(word.capitalize() for word in s.split('_'))


def extract_type_string(type_def):
    if type_def["kind"] == "NonNull":
        return extract_type_string(type_def["type"]) + "!"
    return type_def["name"]


# def to_plural(singular: str) -> str:
#     """Convert a singular word to its plural form."""
#     if singular.endswith("y") and singular[-2] not in "aeiou":
#         # Words ending in 'y' preceded by a consonant (e.g., 'library' -> 'libraries')
#         return singular[:-1] + "ies"
#     elif singular.endswith(("s", "x", "z", "ch", "sh")):
#         # Words ending in 's', 'x', 'z', 'ch', or 'sh' (e.g., 'class' -> 'classes')
#         return singular + "es"
#     else:
#         # Default case (e.g., 'book' -> 'books')
#         return singular + "s"

SCHEMA_COMMON_INPUTS = """
input TableAWSDateFilterInput {
  ne: AWSDate
  eq: AWSDate
  le: AWSDate
  lt: AWSDate
  ge: AWSDate
  gt: AWSDate
  between: [AWSDate]
  attributeExists: Boolean
}

input TableFloatFilterInput {
  ne: Float
  eq: Float
  le: Float
  lt: Float
  ge: Float
  gt: Float
  between: [Float]
  attributeExists: Boolean
}

input TableStringFilterInput {
  ne: String
  eq: String
  le: String
  lt: String
  ge: String
  gt: String
  contains: String
  notContains: String
  between: [String]
  beginsWith: String
  attributeExists: Boolean
  size: ModelSizeInput
}

input ModelSizeInput {
  ne: Int
  eq: Int
  le: Int
  lt: Int
  ge: Int
  gt: Int
  between: [Int]
}

input TableIntFilterInput {
  ne: Int
  eq: Int
  le: Int
  lt: Int
  ge: Int
  gt: Int
  between: [Int]
  attributeExists: Boolean
}

enum ModelSortDirection {
  ASC
  DESC
}
"""


# --------------------------
# GraphQL Block Generators
# --------------------------

def generate_type_block(name: str, fields: List[str]) -> str:
    """Generate the main GraphQL type block."""
    return f"type {name} {{\n{indent(chr(10).join(fields), '  ')}\n}}"


def generate_connection_block(name: str) -> str:
    """Generate the connection type block."""
    return f"""type {name}Connection {{
  items: [{name}]
  totalCount: Int
}}"""


def generate_order_by_input(name: str, fields: List[str]) -> str:
    """Generate the OrderBy input block."""
    order_by_input = f"input OrderBy{name}Input {{\n"
    for field in fields:
        order_by_input += f"  {field}: ModelSortDirection\n"
    order_by_input += "}"
    return order_by_input


def generate_filter_input(name: str, string_fields: List[str], float_fields: List[str], int_fields: List[str], aws_date_fields: List[str]) -> str:
    """Generate the filter input block."""

    filter_input = f"input Table{name}FilterInput {{\n"
    for field in string_fields:
        filter_input += f"  {field}: TableStringFilterInput\n"
    for field in float_fields:
        filter_input += f"  {field}: TableFloatFilterInput\n"
    for field in int_fields:
        filter_input += f"  {field}: TableIntFilterInput\n"
    for field in aws_date_fields:
        filter_input += f"  {field}: TableAWSDateFilterInput\n"
    filter_input += f"""
  and: [Table{name}FilterInput]
  or: [Table{name}FilterInput]
  not: [Table{name}FilterInput]
}}"""
    return filter_input


def generate_query_block(name: str) -> str:
    """Generate the Query block."""
    # plural_name = to_plural(name)

    return f"""type Query {{
  list{name}(
    filter: Table{name}FilterInput
    limit: Int
    orderBy: [OrderBy{name}Input]
    offset: Int
  ): {name}Connection
}}"""


def generate_graphql_from_json(model: Dict) -> str:
    """Generate GraphQL schema from JSON model."""
    original_name = model["name"]
    pascal_name = to_pascal_case(original_name)
    fields = model["fields"]

    # Extract fields and types
    graphql_fields = []
    string_fields = []
    float_fields = []
    int_fields = []
    aws_date_fields = []
    # primary_field = model.get("primaryKey", {}).get("fields", [None])[0]

    for field in fields:
        field_name = field["name"]
        field_type = extract_type_string(field["type"])
        graphql_fields.append(f"{field_name}: {field_type}")

        base_type = field_type.replace("!", "")
        if base_type == "Int":
            int_fields.append(field_name)
        elif base_type == "Float":
            float_fields.append(field_name)
        elif base_type == "AWSDate":
            aws_date_fields.append(field_name)
        else:
            string_fields.append(field_name)

    # Generate all blocks
    return "\n\n".join([
        SCHEMA_COMMON_INPUTS,
        generate_type_block(pascal_name, graphql_fields),
        generate_connection_block(pascal_name),
        generate_order_by_input(
            pascal_name, string_fields + float_fields + int_fields + aws_date_fields),
        generate_filter_input(pascal_name, string_fields,
                              float_fields, int_fields, aws_date_fields),
        generate_query_block(pascal_name)
    ])


# --------------------------
# Introspection Step
# --------------------------

def start_introspection(config_file: Path) -> str:
    """Starts the AppSync introspection and returns the introspection ID."""
    print("Starting AppSync introspection...")

    start_cmd = [
        "aws", "appsync", "start-data-source-introspection",
        "--cli-input-json", f"file://{config_file}"
    ]
    result = subprocess.run(start_cmd, check=True,
                            capture_output=True, text=True)
    introspection_id = json.loads(result.stdout)["introspectionId"]
    print(f"Introspection ID: {introspection_id}")
    return introspection_id


def retrieve_and_save_model(
    introspection_id: str,
    model_name: str,
    output_file: Path,
    max_retries: int = 5,
    retry_delay: int = 5,
) -> None:
    """
    Polls for introspection result using the ID until status is SUCCEEDED,
    extracts the model, and saves it to a file.
    """
    for attempt in range(1, max_retries + 1):
        print(
            f"Checking introspection status (Attempt {attempt}/{max_retries})...")

        get_cmd = [
            "aws", "appsync", "get-data-source-introspection",
            "--include-models-sdl",
            "--introspection-id", introspection_id
        ]
        result = subprocess.run(get_cmd, check=True,
                                capture_output=True, text=True)
        introspection_result = json.loads(result.stdout)

        status = introspection_result.get("introspectionStatus")
        if status == "SUCCESS":
            break
        elif status == "PROCESSING":
            print(
                f"Introspection is still processing. Retrying after {retry_delay} seconds.")
            time.sleep(retry_delay)
        else:
            raise RuntimeError(f"Unexpected introspection status: {status}")
    else:
        raise TimeoutError(
            f"Introspection did not succeed after {max_retries} attempts.")

    # Check for pagination
    next_token = introspection_result.get(
        "introspectionResult", {}).get("nextToken")
    if next_token:
        print(
            f"Warning: nextToken exists ({next_token}) — pagination may be required.")

    # FIXME : Handle pagination if needed if model is not found in the first page
    models = introspection_result.get(
        "introspectionResult", {}).get("models", [])
    model = next((m for m in models if m["name"] == model_name), None)
    if not model:
        raise ValueError(
            f"Model '{model_name}' not found in introspection result.")

    with output_file.open("w") as f:
        json.dump(model, f, indent=2)

    print(f"Model '{model_name}' saved to {output_file}")


# --------------------------
# CLI Argument Parsing
# --------------------------

def get_argument():
    parser = argparse.ArgumentParser(
        description="Generate GraphQL schema from JSON model using AWS AppSync introspection."
    )
    parser.add_argument(
        "--introspection-id",
        help="If provided, skips starting introspection and uses this ID directly."
    )
    parser.add_argument(
        "--model-name", required=True, help="Name of the model to introspect (e.g., 'lims').")
    parser.add_argument(
        "--config-file", required=True, help="Path to the RDS config file (e.g., ./rds-data-config.json).")
    parser.add_argument(
        "--schema-out-file", required=True, help="Where to save the downloaded model JSON (e.g., introspection-schema.json).")
    parser.add_argument("-o", "--graphql-out-file", default="appsync.graphql",
                        help="Where to write the GraphQL output schema.")
    return parser.parse_args()


# --------------------------
# Main Entry Point
# --------------------------

def main():
    args = get_argument()

    config_path = Path(args.config_file)
    schema_path = Path(args.schema_out_file)
    output_path = Path(args.graphql_out_file)

    try:

        if args.introspection_id:
            introspection_id = args.introspection_id
            print(f"Using provided introspection ID: {introspection_id}")
        else:
            introspection_id = start_introspection(config_path)

        retrieve_and_save_model(
            introspection_id, args.model_name, schema_path)

        with schema_path.open("r") as f:
            model_data = json.load(f)

        graphql_schema = generate_graphql_from_json(model_data)

        with output_path.open("w") as f:
            f.write(graphql_schema)

        print(f"GraphQL schema written to {output_path}")

    except Exception as e:
        print(f"Failed: {e}")


if __name__ == "__main__":
    main()
