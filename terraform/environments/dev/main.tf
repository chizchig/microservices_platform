# Development Environment - Microservices Platform

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "microservices-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "microservices-platform"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  environment = "dev"
  cluster_name = "microservices-${local.environment}"
  common_tags = {
    Environment = local.environment
    Project     = "microservices-platform"
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  environment = local.environment
  aws_region  = var.aws_region
  cluster_name = local.cluster_name

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  database_subnet_cidrs = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]

  tags = local.common_tags
}

# EKS Module
module "eks" {
  source = "../../modules/eks"

  environment       = local.environment
  cluster_name      = local.cluster_name
  kubernetes_version = "1.29"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
  private_subnet_ids = module.vpc.private_subnet_ids

  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]

  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 5
      desired_size   = 2
      disk_size      = 50
      labels         = {}
      taints         = []
    }
    spot = {
      instance_types = ["t3.medium", "t3a.medium"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 3
      desired_size   = 1
      disk_size      = 50
      labels = {
        "node-type" = "spot"
      }
      taints = []
    }
  }

  enable_fargate = false

  tags = local.common_tags

  depends_on = [module.vpc]
}

# RDS Module
module "rds" {
  source = "../../modules/rds"

  environment = local.environment
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.database_subnet_ids

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.medium"

  database_name = "microservices_db"
  master_username = "db_admin"

  allocated_storage     = 20
  max_allocated_storage = 100

  multi_az            = false
  publicly_accessible = false
  deletion_protection = false
  skip_final_snapshot = true

  backup_retention_period = 1

  allowed_security_groups = {
    eks = module.eks.node_group_security_group_id
  }

  read_replica_count = 0

  tags = local.common_tags

  depends_on = [module.vpc, module.eks]
}

# ElastiCache Module
module "elasticache" {
  source = "../../modules/elasticache"

  environment = local.environment
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.database_subnet_ids

  engine_version = "7.1"
  node_type      = "cache.t3.micro"

  num_cache_clusters = 1

  automatic_failover_enabled = false
  multi_az_enabled           = false

  snapshot_retention_limit = 1

  allowed_security_groups = {
    eks = module.eks.node_group_security_group_id
  }

  tags = local.common_tags

  depends_on = [module.vpc, module.eks]
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  environment       = local.environment
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  irsa_roles = {
    api_gateway = {
      namespace       = "default"
      service_account = "api-gateway"
      policy_statements = [
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = [module.rds.db_secret_arn]
        }
      ]
    }
    user_service = {
      namespace       = "default"
      service_account = "user-service"
      policy_statements = [
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = [module.rds.db_secret_arn]
        },
        {
          Effect   = "Allow"
          Action   = ["elasticache:*"]
          Resource = [module.elasticache.replication_group_id]
        }
      ]
    }
  }

  github_org  = "my-org"
  gitlab_group = "my-group"

  tags = local.common_tags

  depends_on = [module.eks]
}

# S3 Module
module "s3" {
  source = "../../modules/s3"

  environment     = local.environment
  kms_key_id      = module.eks.kms_key_arn
  backup_role_arn = module.iam.backup_role_arn

  tags = local.common_tags
}

# CloudWatch Module
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  environment   = local.environment
  aws_region    = var.aws_region
  cluster_name  = local.cluster_name
  kms_key_id    = module.eks.kms_key_arn

  microservices = {
    "api-gateway" = {
      log_retention_days = 7
      cpu_threshold      = 80
      memory_threshold   = 80
    }
    "user-service" = {
      log_retention_days = 7
      cpu_threshold      = 80
      memory_threshold   = 80
    }
    "order-service" = {
      log_retention_days = 7
      cpu_threshold      = 80
      memory_threshold   = 80
    }
  }

  applications = {
    "api-gateway" = {
      log_retention_days = 7
      error_threshold    = 5
      latency_threshold  = 1000
    }
    "user-service" = {
      log_retention_days = 7
      error_threshold    = 5
      latency_threshold  = 500
    }
  }

  alert_emails = var.alert_emails

  tags = local.common_tags
}
