variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type =  string
}
variable "sku" {
  description = "The type of storage - translates to how much it costs"
  default = "Free"
}
variable "retention" {
  description = "How long to keep the metrics/logs"
  default = 7 # 7 only valid for "Free" SKU. 30 is minimum for all others
}