provider "aws" {
  region = "eu-central-1" 
}

module "base_label" {
  source    = "cloudposse/label/null"
  version   = "0.25.0"
  namespace = "lpnu"
  stage     = "dev"
}

# --- DynamoDB Таблиці ---
module "dynamodb_courses" {
  source     = "./modules/dynamodb"
  table_name = "courses"
  hash_key   = "id"
  context    = module.base_label.context
}

module "dynamodb_authors" {
  source     = "./modules/dynamodb"
  table_name = "authors"
  hash_key   = "id"
  context    = module.base_label.context
}

module "dynamodb_categories" {
  source     = "./modules/dynamodb"
  table_name = "categories"
  hash_key   = "id"
  context    = module.base_label.context
}

# --- Локальні змінні для мапінгу (Додано відсутні лямбди) ---
locals {
  lambdas = {
    "get-all-authors" = { action = "dynamodb:Scan",       table_arn = module.dynamodb_authors.table_arn,   table_name = module.dynamodb_authors.table_name }
    "get-all-courses" = { action = "dynamodb:Scan",       table_arn = module.dynamodb_courses.table_arn,   table_name = module.dynamodb_courses.table_name }
    "save-course"     = { action = "dynamodb:PutItem",    table_arn = module.dynamodb_courses.table_arn,   table_name = module.dynamodb_courses.table_name }
    "get-course"      = { action = "dynamodb:GetItem",    table_arn = module.dynamodb_courses.table_arn,   table_name = module.dynamodb_courses.table_name }
    "update-course"   = { action = "dynamodb:UpdateItem", table_arn = module.dynamodb_courses.table_arn,   table_name = module.dynamodb_courses.table_name }
    "delete-course"   = { action = "dynamodb:DeleteItem", table_arn = module.dynamodb_courses.table_arn,   table_name = module.dynamodb_courses.table_name }
  }
}

# --- IAM Ролі та Політики ---
resource "aws_iam_role" "lambda_exec" {
  for_each = local.lambdas
  name     = "${module.base_label.id}-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  for_each = local.lambdas
  name     = "LambdaPolicy"
  role     = aws_iam_role.lambda_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = [each.value.action]
        Resource = [each.value.table_arn]
      }
    ]
  })
}

# --- Lambda Функції ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions" 
  output_path = "${path.module}/lambda_payload.zip"
}

resource "aws_lambda_function" "api" {
  for_each      = local.lambdas
  
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${module.base_label.id}-${each.key}"
  role          = aws_iam_role.lambda_exec[each.key].arn
  
  handler       = "${each.key}.handler" 
  runtime       = "nodejs16.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME         = each.value.table_name
      AUTHORS_TABLE_NAME = module.dynamodb_authors.table_name 
    }
  }
}