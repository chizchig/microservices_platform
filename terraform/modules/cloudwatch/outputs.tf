output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = aws_sns_topic.alarms.arn
}

output "log_group_names" {
  description = "Map of log group names"
  value = merge(
    { for k, v in aws_cloudwatch_log_group.microservices : k => v.name },
    { for k, v in aws_cloudwatch_log_group.applications : k => v.name }
  )
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
