# 1. ПРОВАЙДЕР ДЛЯ БІЛІНГУ (Метрики грошей працюють ТІЛЬКИ в us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# 2. ГОЛОВНИЙ ТОПІК СПОВІЩЕНЬ
resource "aws_sns_topic" "alerts" {
  name = "lpnu-dev-alerts"
}

# 3. ПІДПИСКА НА EMAIL
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "oksana.vyshynska.ri.2024@lpnu.ua" 
}

# 4. ПІДПИСКА НА СЛЕК-ЛЯМБДУ
resource "aws_sns_topic_subscription" "slack_lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

# 5. BILLING ALARM (Моніторинг витрат грошей > $5)
# Створюємо окремий топік для грошей у Вірджинії
resource "aws_sns_topic" "billing_alerts" {
  provider = aws.us_east_1
  name     = "lpnu-dev-billing-alerts"
}
resource "aws_sns_topic_subscription" "billing_email" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = "oksana.vyshynska.ri.2024@lpnu.ua"
}
resource "aws_cloudwatch_metric_alarm" "billing_alarm" {
  provider            = aws.us_east_1
  alarm_name          = "aws-billing-alarm-5usd"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "21600" # 6 годин
  statistic           = "Maximum"
  threshold           = "5.0"
  alarm_description   = "Тривога! Витрати перевищують $5"
  alarm_actions       = [aws_sns_topic.billing_alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}

# 6. ФІЛЬТР ЛОГІВ НА СЛОВО "ERROR"
resource "aws_cloudwatch_log_metric_filter" "lambda_errors" {
  name           = "LambdaErrorFilter"
  pattern        = "ERROR"
  log_group_name = "/aws/lambda/lpnu-dev-get-all-courses" # ПЕРЕВІР НАЗВУ СВОЄЇ ЛЯМБДИ

  metric_transformation {
    name      = "ErrorCount"
    namespace = "LPNU/LambdaMetrics"
    value     = "1"
  }
}

# 7. ALARM НА ПОМИЛКИ В ЛЯМБДІ
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "lambda-get-courses-error-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = aws_cloudwatch_log_metric_filter.lambda_errors.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.lambda_errors.metric_transformation[0].namespace
  period              = "60" # Перевірка кожну хвилину
  statistic           = "Sum"
  threshold           = "1"  # Спрацює від 1 помилки
  alarm_description   = "Знайдено помилку в Ламбді get-all-courses!"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# 8. СТВОРЕННЯ ZIP-АРХІВУ З ПАЙТОН КОДОМ
data "archive_file" "slack_notifier_zip" {
  type        = "zip"
  source_file = "slack_notifier.py"
  output_path = "slack_notifier.zip"
}

# 9. РОЛЬ ДЛЯ СЛЕК-ЛЯМБДИ
resource "aws_iam_role" "slack_lambda_role" {
  name = "lpnu-dev-slack-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 10. САМА ЛЯМБДА ДЛЯ СЛЕКУ
resource "aws_lambda_function" "slack_notifier" {
  filename         = "slack_notifier.zip"
  function_name    = "lpnu-dev-slack-notifier"
  role             = aws_iam_role.slack_lambda_role.arn
  handler          = "slack_notifier.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.slack_notifier_zip.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/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" 
    }
  }
}

# 11. ДОЗВІЛ SNS ВИКЛИКАТИ ЛЯМБДУ
resource "aws_lambda_permission" "with_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}