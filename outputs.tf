output "dynamodb_tables" {
  value = {
    courses    = module.dynamodb_courses.table_name
    authors    = module.dynamodb_authors.table_name
    categories = module.dynamodb_categories.table_name
  }
}

output "lambda_functions_arns" {
  value = { for k, v in aws_lambda_function.api : k => v.arn }
}
