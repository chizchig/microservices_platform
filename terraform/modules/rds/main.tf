# RDS Module - Managed PostgreSQL Database

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "${var.environment}-db-subnet-group"
  description = "Database subnet group for ${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.environment}-db-subnet-group"
  })
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.environment}-db-params-"
  family      = var.parameter_group_family
  description = "Custom parameters for ${var.environment}"

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-rds-"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.environment}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_ingress" {
  for_each = var.allowed_security_groups

  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.rds.id
  description              = "Allow access from ${each.key}"
}

resource "aws_security_group_rule" "rds_ingress_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.rds.id
  description       = "Allow access from CIDR blocks"
}

# KMS Key for RDS Encryption
resource "aws_kms_key" "rds" {
  count = var.storage_encrypted && var.kms_key_id == null ? 1 : 0

  description             = "RDS encryption key for ${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.environment}-rds-key"
  })
}

resource "aws_kms_alias" "rds" {
  count = var.storage_encrypted && var.kms_key_id == null ? 1 : 0

  name          = "alias/${var.environment}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

# Random password generation
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secrets Manager for DB credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name_prefix = "${var.environment}-db-credentials-"
  description = "Database credentials for ${var.environment}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    host     = aws_db_instance.main.address
    port     = var.port
    dbname   = var.database_name
  })
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-db"

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id != null ? var.kms_key_id : (var.storage_encrypted ? aws_kms_key.rds[0].arn : null)

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = var.multi_az
  publicly_accessible    = var.publicly_accessible
  deletion_protection    = var.deletion_protection
  skip_final_snapshot    = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.environment}-db-final-snapshot"

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? (var.kms_key_id != null ? var.kms_key_id : (var.storage_encrypted ? aws_kms_key.rds[0].arn : null)) : null
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  copy_tags_to_snapshot      = true

  tags = merge(var.tags, {
    Name = "${var.environment}-db"
  })

  depends_on = [aws_cloudwatch_log_group.rds]

  lifecycle {
    prevent_destroy = false
  }
}

# CloudWatch Log Groups for RDS
resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${var.environment}-db/${each.value}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  role       = aws_iam_role.rds_monitoring[0].name
}

# RDS Read Replicas (optional)
resource "aws_db_instance" "replica" {
  count = var.read_replica_count

  identifier = "${var.environment}-db-replica-${count.index + 1}"

  replicate_source_db = aws_db_instance.main.arn
  instance_class      = var.replica_instance_class != null ? var.replica_instance_class : var.instance_class

  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id != null ? var.kms_key_id : (var.storage_encrypted ? aws_kms_key.rds[0].arn : null)

  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = var.publicly_accessible

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? (var.kms_key_id != null ? var.kms_key_id : (var.storage_encrypted ? aws_kms_key.rds[0].arn : null)) : null
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  tags = merge(var.tags, {
    Name = "${var.environment}-db-replica-${count.index + 1}"
  })
}
