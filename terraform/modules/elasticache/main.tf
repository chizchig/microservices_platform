# ElastiCache Module - Managed Redis Cluster

# Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.environment}-cache-subnet-group"
  description = "Cache subnet group for ${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

# Parameter Group
resource "aws_elasticache_parameter_group" "main" {
  name_prefix = "${var.environment}-cache-params-"
  family      = var.parameter_group_family
  description = "Custom parameters for ${var.environment}"

  dynamic "parameter" {
    for_each = var.cache_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group
resource "aws_security_group" "cache" {
  name_prefix = "${var.environment}-cache-"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.environment}-cache-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cache_ingress" {
  for_each = var.allowed_security_groups

  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.cache.id
  description              = "Allow access from ${each.key}"
}

resource "aws_security_group_rule" "cache_ingress_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.cache.id
  description       = "Allow access from CIDR blocks"
}

# KMS Key for Encryption
resource "aws_kms_key" "cache" {
  count = var.at_rest_encryption_enabled && var.kms_key_id == null ? 1 : 0

  description             = "ElastiCache encryption key for ${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.environment}-cache-key"
  })
}

resource "aws_kms_alias" "cache" {
  count = var.at_rest_encryption_enabled && var.kms_key_id == null ? 1 : 0

  name          = "alias/${var.environment}-cache"
  target_key_id = aws_kms_key.cache[0].key_id
}

# Random password for Redis AUTH
resource "random_password" "cache" {
  count = var.transit_encryption_enabled ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secrets Manager for cache credentials
resource "aws_secretsmanager_secret" "cache_credentials" {
  count = var.transit_encryption_enabled ? 1 : 0

  name_prefix = "${var.environment}-cache-credentials-"
  description = "Cache credentials for ${var.environment}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "cache_credentials" {
  count = var.transit_encryption_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.cache_credentials[0].id
  secret_string = jsonencode({
    host     = aws_elasticache_replication_group.main.primary_endpoint_address
    port     = var.port
    password = random_password.cache[0].result
  })
}

# ElastiCache Replication Group (Redis Cluster)
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.environment}-cache"
  description          = "Redis cluster for ${var.environment}"

  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.main.name

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  kms_key_id                 = var.kms_key_id != null ? var.kms_key_id : (var.at_rest_encryption_enabled ? aws_kms_key.cache[0].arn : null)

  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.transit_encryption_enabled ? random_password.cache[0].result : null

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  maintenance_window       = var.maintenance_window

  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  notification_topic_arn = var.notification_topic_arn

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.cache_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.cache_engine.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-cache"
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "cache_slow" {
  name              = "/aws/elasticache/${var.environment}-cache/slow-log"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "cache_engine" {
  name              = "/aws/elasticache/${var.environment}-cache/engine-log"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
