data "aws_secretsmanager_secret" "datadog_api_key" {
  name = "datadog-api-key"
}