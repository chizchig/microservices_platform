variable "environment" {
  description = "Environment name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL"
  type        = string
}

variable "irsa_roles" {
  description = "Map of IRSA roles to create"
  type = map(object({
    namespace       = string
    service_account = string
    policy_statements = list(object({
      Effect   = string
      Action   = list(string)
      Resource = list(string)
    }))
  }))
  default = {}
}

variable "enable_cross_account_access" {
  description = "Enable cross-account access role"
  type        = bool
  default     = false
}

variable "trusted_account_arns" {
  description = "List of trusted account ARNs"
  type        = list(string)
  default     = []
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "my-org"
}

variable "gitlab_group" {
  description = "GitLab group name"
  type        = string
  default     = "my-group"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
