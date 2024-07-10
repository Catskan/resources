resource "aws_secretsmanager_secret" "scheduled_task_secret" {
  for_each                = local.scheduled_tasks
  name                    = "${var.project_name}/${each.value.name}"
  description             = each.value.secret_description
  recovery_window_in_days = 0 # Force delete the created secret
}

module "scheduled_task" {
  for_each             = local.scheduled_tasks
  source               = "git@github.com:etx-majelan/terraform-module-lambda.git?ref=v1.2.3"
  function_name        = "${var.project_name}-${each.value.name}"
  runtime              = each.value.runtime
  architecture         = "arm64"
  package_type         = each.value.package_type
  function_description = each.value.function_description
  function_handler     = each.value.handler
  function_timeout     = each.value.function_timeout #In seconds
  function_versionning = false
  environment          = var.environment
  repository_name      = var.repository_url

  iam_execution_role = "run_${var.project_name}"
  lambda_environment_variables = {
    CORE_API_SECRET_ARN             = aws_secretsmanager_secret.scheduled_task_secret[each.key].arn,
    CORE_API_ENDPOINT               = var.environment != "production" ? "https://api.${var.environment}.${var.hosted_zone_name}/v2/scheduling" : "https://api.${var.hosted_zone_name}/v2/scheduling"
    LOG_LEVEL                       = "INFO",
    DD_SITE                         = "datadoghq.eu",
    DD_API_KEY_SECRET_ARN           = data.aws_secretsmanager_secret.datadog_api_key.arn,
    DD_SERVICE                      = "${var.project_name}-api-scheduling",
    DD_ENV                          = var.environment,
    DD_FLUSH_TO_LOG                 = "true",
    DD_LOGS_CONFIG_PROCESSING_RULES = "[{ \"type\" : \"exclude_at_match\", \"name\" : \"exclude_start_and_end_logs\", \"pattern\" : \"(START|REPORT|END) RequestId\" }]"
    DD_SERVERLESS_LOGS_ENABLED      = true,
    DD_TRACE_ENABLED                = false,
    DD_TRACE_STARTUP_LOGS           = false,
  }
  lambda_archive_source_folder = path.root
}

resource "aws_scheduler_schedule_group" "lambda_scheduler_group" {
  for_each = local.scheduled_tasks
  name     = "${var.project_name}-${each.value.name}"
}

resource "aws_scheduler_schedule" "lambda_scheduler" {
  for_each                     = local.scheduled_tasks
  name                         = "${var.project_name}-${each.value.name}"
  description                  = each.value.eventbridge_scheduler_description
  group_name                   = aws_scheduler_schedule_group.lambda_scheduler_group[each.value.name].name
  schedule_expression          = each.value.eventbridge_scheduler_schedule
  schedule_expression_timezone = "Europe/Paris"
  state                        = var.environment != "sandbox" ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 2
  }

  target {
    arn      = module.scheduled_task[each.key].lambda_arn
    role_arn = module.scheduled_task[each.key].execution_role_arn
    input    = jsonencode("")

    retry_policy {
      maximum_retry_attempts = 5
    }
  }
}