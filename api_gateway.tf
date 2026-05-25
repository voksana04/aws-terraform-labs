# 1. Створення самого REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "${module.base_label.id}-api"
  description = "API Gateway for Serverless Application"
}

# 2. Створення ресурсів (URL-шляхів: /authors, /courses, /courses/{id})
resource "aws_api_gateway_resource" "authors" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "authors"
}

resource "aws_api_gateway_resource" "courses" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "courses"
}

resource "aws_api_gateway_resource" "course_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.courses.id
  path_part   = "{id}"
}

# 3. Створення Моделі Валідації
resource "aws_api_gateway_model" "course_model" {
  rest_api_id  = aws_api_gateway_rest_api.api.id
  name         = "CourseInputModel"
  content_type = "application/json"
  schema = jsonencode({
    "$schema"  = "http://json-schema.org/schema#"
    title      = "CourseInputModel"
    type       = "object"
    properties = {
      title    = { type = "string" }
      authorId = { type = "string" }
      length   = { type = "string" }
      category = { type = "string" }
    }
    required = ["title", "authorId", "length", "category"]
  })
}

# Валідатор
resource "aws_api_gateway_request_validator" "body" {
  name                        = "ValidateBody"
  rest_api_id                 = aws_api_gateway_rest_api.api.id
  validate_request_body       = true
  validate_request_parameters = false
}

# 4. ШАБЛОНИ ТА МАРШРУТИ (endpoints)
locals {
  template_id_only = "{\"id\": \"$input.params('id')\"}"

  template_put = <<EOF
{
  "id": "$input.params('id')",
  "title" : $input.json('$.title'),
  "authorId" : $input.json('$.authorId'),
  "length" : $input.json('$.length'),
  "category" : $input.json('$.category'),
  "watchHref" : $input.json('$.watchHref')
}
EOF

  endpoints = {
    "get_authors"      = { res_id = aws_api_gateway_resource.authors.id,   method = "GET",    lambda = "get-all-authors", validator = null, model = null, template = null, type = "AWS" }
    
    "get_courses"      = { res_id = aws_api_gateway_resource.courses.id,   method = "GET",    lambda = "get-all-courses", validator = null, model = null, template = null, type = "AWS_PROXY" }
    "post_courses"     = { res_id = aws_api_gateway_resource.courses.id,   method = "POST",   lambda = "save-course",     validator = aws_api_gateway_request_validator.body.id, model = aws_api_gateway_model.course_model.name, template = null, type = "AWS_PROXY" }
    "get_course_id"    = { res_id = aws_api_gateway_resource.course_id.id, method = "GET",    lambda = "get-course",       validator = null, model = null, template = local.template_id_only, type = "AWS" }
    "delete_course_id" = { res_id = aws_api_gateway_resource.course_id.id, method = "DELETE", lambda = "delete-course",   validator = null, model = null, template = local.template_id_only, type = "AWS" }
    "put_course_id"    = { res_id = aws_api_gateway_resource.course_id.id, method = "PUT",    lambda = "update-course",   validator = null, model = null, template = local.template_put, type = "AWS" }
  }
}

# 5. ГЕНЕРАЦІЯ МЕТОДІВ ТА ІНТЕГРАЦІЙ
resource "aws_api_gateway_method" "methods" {
  for_each             = local.endpoints
  rest_api_id           = aws_api_gateway_rest_api.api.id
  resource_id           = each.value.res_id
  http_method           = each.value.method
  authorization         = "NONE"
  request_validator_id = each.value.validator
  request_models       = each.value.model != null ? { "application/json" = each.value.model } : {}
}

resource "aws_api_gateway_integration" "integrations" {
  for_each                = local.endpoints
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = each.value.res_id
  http_method             = aws_api_gateway_method.methods[each.key].http_method
  integration_http_method = "POST"
  
  # Динамічно виставляємо тип: AWS_PROXY для списків, AWS для параметризованих запитів
  type                    = each.value.type
  
  uri                     = aws_lambda_function.api[each.value.lambda].invoke_arn
  request_templates       = each.value.template != null ? { "application/json" = each.value.template } : null
}

# Відповідь 200 OK + CORS (потрібна ТІЛЬКИ для типу інтеграції "AWS")
resource "aws_api_gateway_method_response" "responses_200" {
  for_each    = { for k, v in local.endpoints : k => v if v.type == "AWS" }
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = each.value.res_id
  http_method = aws_api_gateway_method.methods[each.key].http_method
  status_code = "200"
  response_models = { "application/json" = "Empty" }
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}

resource "aws_api_gateway_integration_response" "integration_responses_200" {
  for_each    = { for k, v in local.endpoints : k => v if v.type == "AWS" }
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = each.value.res_id
  http_method = aws_api_gateway_method.methods[each.key].http_method
  status_code = aws_api_gateway_method_response.responses_200[each.key].status_code
  
  depends_on  = [
    aws_api_gateway_integration.integrations,
    aws_api_gateway_method_response.responses_200
  ]
  
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }

  # Безпечний розбір відповіді для атомарних CRUD-операцій
  response_templates = {
    "application/json" = <<EOF
#set($body = $input.path('$.body'))
#if("$!body" != "" && $body != $null)
$body
#else
$input.json('$')
#end
EOF
  }
}

# 6. НАЛАШТУВАННЯ CORS (Методи OPTIONS)
locals {
  api_resources = {
    "authors"    = aws_api_gateway_resource.authors.id
    "courses"    = aws_api_gateway_resource.courses.id
    "courses_id" = aws_api_gateway_resource.course_id.id
  }
}

resource "aws_api_gateway_method" "options" {
  for_each      = local.api_resources
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  for_each          = local.api_resources
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = each.value
  http_method       = aws_api_gateway_method.options[each.key].http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options" {
  for_each    = local.api_resources
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"
  response_models = { "application/json" = "Empty" }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each    = local.api_resources
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code
  
  depends_on = [
    aws_api_gateway_method.options,
    aws_api_gateway_method_response.options,
    aws_api_gateway_integration.options
  ]

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT,DELETE'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# 7. ДОЗВІЛ API GATEWAY ВИКЛИКАТИ LAMBDA
resource "aws_lambda_permission" "apigw" {
  for_each      = local.endpoints
  statement_id  = "AllowExecutionFromAPIGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api[each.value.lambda].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# 8. РОЗГОРТАННЯ API
resource "aws_api_gateway_deployment" "api_deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_integration.integrations))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.integrations,
    aws_api_gateway_method_response.responses_200,
    aws_api_gateway_integration_response.integration_responses_200,
    aws_api_gateway_integration.options,
    aws_api_gateway_integration_response.options
  ]
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.api_deploy.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "v1"
}

output "api_base_url" {
  value = aws_api_gateway_stage.v1.invoke_url
}