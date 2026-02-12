output "irsa_role_arns" {
  description = "Map of IRSA role ARNs"
  value       = { for k, v in aws_iam_role.irsa : k => v.arn }
}

output "cicd_role_arn" {
  description = "CI/CD role ARN"
  value       = aws_iam_role.cicd.arn
}

output "backup_role_arn" {
  description = "Backup role ARN"
  value       = aws_iam_role.backup.arn
}

output "monitoring_role_arn" {
  description = "Monitoring role ARN"
  value       = aws_iam_role.monitoring.arn
}

output "monitoring_instance_profile_name" {
  description = "Monitoring instance profile name"
  value       = aws_iam_instance_profile.monitoring.name
}

output "cross_account_role_arn" {
  description = "Cross-account role ARN"
  value       = var.enable_cross_account_access ? aws_iam_role.cross_account[0].arn : null
}
