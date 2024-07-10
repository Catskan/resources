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

variable "hosted_zone_name" {
  default = "majelan.audio"
  type    = string
}