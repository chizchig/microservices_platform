variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "microservices" {
  description = "Map of microservices with monitoring config"
  type = map(object({
    log_retention_days = number
    cpu_threshold      = number
    memory_threshold   = number
  }))
  default = {}
}

variable "applications" {
  description = "Map of applications with monitoring config"
  type = map(object({
    log_retention_days = number
    error_threshold    = number
    latency_threshold  = number
  }))
  default = {}
}

variable "container_insights_retention" {
  description = "Container Insights log retention in days"
  type        = number
  default     = 7
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
}

variable "alert_emails" {
  description = "List of email addresses for alerts"
  type        = list(string)
  default     = []
}

variable "pagerduty_integration_key" {
  description = "PagerDuty integration key"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
