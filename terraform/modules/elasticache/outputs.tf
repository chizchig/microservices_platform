output "replication_group_id" {
  description = "Replication group ID"
  value       = aws_elasticache_replication_group.main.id
}

output "primary_endpoint_address" {
  description = "Primary endpoint address"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "port" {
  description = "Cache port"
  value       = aws_elasticache_replication_group.main.port
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.cache.id
}

output "subnet_group_name" {
  description = "Subnet group name"
  value       = aws_elasticache_subnet_group.main.name
}

output "parameter_group_name" {
  description = "Parameter group name"
  value       = aws_elasticache_parameter_group.main.name
}

output "secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = var.transit_encryption_enabled ? aws_secretsmanager_secret.cache_credentials[0].arn : null
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  value       = var.kms_key_id != null ? var.kms_key_id : (var.at_rest_encryption_enabled ? aws_kms_key.cache[0].arn : null)
}
