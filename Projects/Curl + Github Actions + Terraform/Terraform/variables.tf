variable "project_name" {
  description = "Project name"
  type        = string
}
variable "repository_url" {
  description = "Source repository"
  type        = string
}
variable "team" {
  description = "Team name"
  type        = string
}
variable "environment" {
  description = "environment name"
  type        = string
}

variable "shutdown_scheduled" {
  description = "Tag used to automatically shutdown instances"
  type        = string
  default     = "never"
}

# DB
variable "db_allocated_storage" {
  description = "Allocated storage for the DB"
  type        = string
}
variable "db_multi_az" {
  description = "Allow mutli availability zone"
  type        = bool
}
variable "db_deletion_protection" {
  description = "Protect the DB deletion"
  type        = bool
  default     = true
}
variable "db_instance_class" {
  description = "Instance class used for this database"
  type        = string
  default     = null
}

variable "db_storage_type" {
  description = "Storage type for RDS instances (gp2, gp3, io1)"
  type        = string
  default     = "gp3"
}

variable "db_minor_version_auto_upgrade" {
  description = "Enable automatic RDS upgrade for minor versions"
  type        = bool
  default     = true
}

variable "db_performance_insights_enabled" {
  description = "Enable Performe insights feature"
  type        = bool
  default     = false
}

variable "db_performance_insights_retention_period" {
  description = "Retention period of performance insights data"
  type        = number
  default     = 7 #Minimum
}

variable "db_monitoring_interval" {
  description = "Send metrics every x seconds"
  type        = number
  default     = 0 #Disabled
}

variable "db_backup_retention_period" {
  description = "How many days to keep backups before removed"
  type        = number
  default     = 0 #Disabled backup
}
# Redis

variable "redis_instance_type" {
  description = "Instance class to Redis ElastiCache"
  type        = string
  default     = "cache.t2.micro"
}


# RUN
variable "container_env_vars" {
  description = "Environment variables to inject into the container"
  type        = list(map(any))
}
variable "api_container_image_tag" {
  description = "CoreAPI ECR image tag"
  type        = string
}

variable "rlcu_container_image_tag" {
  description = "RLCU ECR image tag"
  type        = string
}

variable "alb_listener_rule" {
  description = "The rules that you define for your listener determine how the load balancer routes requests to the targets in one or more target groups"
  type        = map(any)
}
variable "create_domain_aliases" {
  description = "List of domains for which alias records should be created"
  type        = list(string)
}
variable "asg_max_capacity" {
  default     = 20
  type        = number
  description = "Max capacity of the scalable target."
}

variable "asg_min_capacity" {
  default     = 1
  type        = number
  description = "Min capacity of the scalable target."
}

variable "app_version" {
  default     = null
  type        = string
  description = "Defined a application version"
}

variable "hosted_zone_name" {
  default = "majelan.audio"
  type    = string
}

variable "team_data_account_cidr" {
  description = "Team-Data accounts VPC CIDR"
  type        = list(string)
  default     = []
}

#RLCU
variable "rlcu_lambda_schedule_expression" {
  description = "Schedule expression to run the RLCU Lambda"
  type        = string
  default     = "cron(00 14 ? * MON-FRI *)"
}

variable "rlcu_scheduler_state" {
  description = "Is scheduler for RLCU lambda is enabled ?"
  type        = string
  default     = "ENABLED"
}