locals {
  scheduled_tasks = {
    api-scheduling = {
      #General, SecretsManager
      name               = "api-scheduling"
      secret_description = "Store secrets needed by api-scheduling lambda"

      #Function
      function_description = "Perform HTTP request on Core API scheduling"
      runtime              = "python3.11"
      package_type         = "Zip"
      handler              = "main.lambda_handler"
      function_timeout     = 10

      #Eventbridge Scheduler
      eventbridge_scheduler_description = "Triggering majelan-api-scheduling lambda"
      eventbridge_scheduler_schedule    = "rate(15 minutes)"
    }
  }
}
