# Login to Warehouse account and navigate to
# Console > AWS Glue > Data Catalog > Settings > Resource policy

# FIXME don't think this is needed - to be removed

# resource "aws_glue_resource_policy" "cross_account" {
#   enable_hybrid = "TRUE"
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           Service = "ram.amazonaws.com"
#           AWS     = [for id in local.consumer_account_ids : "arn:aws:iam::${id}:root"]
#         }
#         Action = [
#           "glue:GetTable",
#           "glue:GetTables",
#           "glue:GetDatabase",
#           "glue:GetDatabases",
#           "glue:ShareResource"
#         ]
#         Resource = flatten([
#           "arn:aws:glue:ap-southeast-2:${data.aws_caller_identity.current.id}:catalog",
#           [for db in local.shared_databases : "arn:aws:glue:ap-southeast-2:${data.aws_caller_identity.current.id}:database/${db}"],
#           [for db in local.shared_databases : "arn:aws:glue:ap-southeast-2:${data.aws_caller_identity.current.id}:table/${db}/*"]
#         ])
#       }
#     ]
#   })
# }
