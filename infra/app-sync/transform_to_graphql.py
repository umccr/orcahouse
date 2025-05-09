import argparse
import json
from textwrap import indent
from typing import Dict, List, Optional


def to_pascal_case(s):
    return ''.join(word.capitalize() for word in s.split('_'))


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


def extract_type_string(type_def):
    if type_def["kind"] == "NonNull":
        return extract_type_string(type_def["type"]) + "!"
    return type_def["name"]


FLOAT_INPUT_FILTER = """
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
"""

STRING_INPUT_FILTER = """
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
"""

MODEL_SIZE_INPUT = """
input ModelSizeInput {
  ne: Int
  eq: Int
  le: Int
  lt: Int
  ge: Int
  gt: Int
  between: [Int]
}
"""

INT_INPUT_FILTER = """
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
"""

MODEL_SORT_DIRECTION = """
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


def generate_filter_input(name: str, string_fields: List[str], float_fields: List[str], int_fields: List[str]) -> str:
    """Generate the filter input block."""
    filter_input = f"input Table{name}FilterInput {{\n"
    for field in string_fields:
        filter_input += f"  {field}: TableStringFilterInput\n"
    for field in float_fields:
        filter_input += f"  {field}: TableFloatFilterInput\n"
    for field in int_fields:
        filter_input += f"  {field}: TableIntFilterInput\n"
    filter_input += f"""  and: [Table{name}FilterInput]
  or: [Table{name}FilterInput]
  not: [Table{name}FilterInput]
}}"""
    return filter_input


def generate_query_block(name: str, primary_field: Optional[str]) -> str:
    """Generate the Query block."""
    # plural_name = to_plural(name)

    return f"""type Query {{
  get{name}({primary_field}: String!): {name}
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
    primary_field = model.get("primaryKey", {}).get("fields", [None])[0]

    for field in fields:
        field_name = field["name"]
        field_type = extract_type_string(field["type"])
        graphql_fields.append(f"{field_name}: {field_type}")

        base_type = field_type.replace("!", "")
        if base_type == "Int":
            int_fields.append(field_name)
        elif base_type == "Float":
            float_fields.append(field_name)
        else:
            string_fields.append(field_name)

    # Generate all blocks
    return "\n\n".join([
        MODEL_SIZE_INPUT,
        MODEL_SORT_DIRECTION,
        FLOAT_INPUT_FILTER,
        STRING_INPUT_FILTER,
        generate_type_block(pascal_name, graphql_fields),
        generate_connection_block(pascal_name),
        generate_order_by_input(
            pascal_name, string_fields + float_fields + int_fields),
        generate_filter_input(pascal_name, string_fields,
                              float_fields, int_fields),
        generate_query_block(pascal_name, primary_field)
    ])


def get_argument():
    parser = argparse.ArgumentParser(
        description="Generate GraphQL schema from JSON model file."
    )
    parser.add_argument(
        "-o",
        "--out-file",
        default="appsync.graphql",
        help="The GraphQL schema uploaded for appsync.",
    )

    parser.add_argument(
        "-i",
        "--input-file",
        default="introspection-schema.json",
        help="The rds introspection schema file autogenerated by AppSync.",
    )

    args = parser.parse_args()

    return args


# --------------------------
# Example usage:
# --------------------------
if __name__ == "__main__":

    args = get_argument()

    with open(args.input_file, "r") as f:  # Replace with your JSON input file path
        model_data = json.load(f)

    output = generate_graphql_from_json(model_data)

    with open(args.out_file, "w") as f:
        f.write(output)
