module "scheduled_tasks" {
  source           = "./modules/scheduled_tasks"
  project_name     = var.project_name
  environment      = var.environment
  team             = var.team
  repository_url   = var.repository_url
  hosted_zone_name = var.hosted_zone_name
}