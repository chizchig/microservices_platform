output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "db_instance_address" {
  description = "RDS instance address"
  value       = aws_db_instance.main.address
}

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "db_instance_username" {
  description = "Master username"
  value       = aws_db_instance.main.username
}

output "db_security_group_id" {
  description = "Security group ID of RDS"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_id" {
  description = "DB subnet group ID"
  value       = aws_db_subnet_group.main.id
}

output "db_secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_replica_addresses" {
  description = "List of replica addresses"
  value       = aws_db_instance.replica[*].address
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  value       = var.kms_key_id != null ? var.kms_key_id : (var.storage_encrypted ? aws_kms_key.rds[0].arn : null)
}
