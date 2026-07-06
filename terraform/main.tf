terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

variable "student_name" {
  type    = string
  default = "peserta"
}

variable "aws_region_primary" {
  type    = string
  default = "us-east-1"
}

variable "aws_region_secondary" {
  type    = string
  default = "us-west-2"
}

locals {
  prefix          = "cloudtech"
  app_vpc_cidr    = "10.10.0.0/16"
  data_vpc_cidr   = "10.20.0.0/16"
  mon_vpc_cidr    = "10.30.0.0/16"
}

provider "aws" {
  alias  = "primary"
  region = var.aws_region_primary

  default_tags {
    tags = {
      Project     = "cloudtech-2026"
      Environment = "production"
      ManagedBy   = "terraform"
      Student     = var.student_name
    }
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.aws_region_secondary

  default_tags {
    tags = {
      Project     = "cloudtech-2026"
      Environment = "production"
      ManagedBy   = "terraform"
      Student     = var.student_name
    }
  }
}

###############################################################################
# VPC 1: Application VPC (EKS, ALB) - us-east-1
###############################################################################
module "app_vpc" {
  source = "./modules/vpc"
  providers = { aws = aws.primary }

  resource_prefix = "${local.prefix}-app"
  vpc_cidr        = local.app_vpc_cidr
  region          = var.aws_region_primary

  subnets = [
    { name = "${local.prefix}-app-public-1a",  type = "public",  cidr = "10.10.1.0/24", az = "us-east-1a" },
    { name = "${local.prefix}-app-public-1b",  type = "public",  cidr = "10.10.2.0/24", az = "us-east-1b" },
    { name = "${local.prefix}-app-private-1a", type = "private", cidr = "10.10.10.0/24", az = "us-east-1a" },
    { name = "${local.prefix}-app-private-1b", type = "private", cidr = "10.10.11.0/24", az = "us-east-1b" },
  ]
}

###############################################################################
# VPC 2: Data VPC (RDS, ElastiCache) - us-east-1
###############################################################################
module "data_vpc" {
  source = "./modules/vpc"
  providers = { aws = aws.primary }

  resource_prefix = "${local.prefix}-data"
  vpc_cidr        = local.data_vpc_cidr
  region          = var.aws_region_primary

  subnets = [
    { name = "${local.prefix}-data-isolated-1a", type = "isolated", cidr = "10.20.1.0/24", az = "us-east-1a" },
    { name = "${local.prefix}-data-isolated-1b", type = "isolated", cidr = "10.20.2.0/24", az = "us-east-1b" },
    { name = "${local.prefix}-data-private-1a",  type = "private",  cidr = "10.20.10.0/24", az = "us-east-1a" },
    { name = "${local.prefix}-data-private-1b",  type = "private",  cidr = "10.20.11.0/24", az = "us-east-1b" },
  ]
}

###############################################################################
# VPC Peering: App VPC <-> Data VPC (same region)
###############################################################################
module "vpc_peering" {
  source    = "./modules/vpc-peering"
  providers = { aws = aws.primary }

  resource_prefix        = local.prefix
  requester_vpc_id       = module.app_vpc.vpc_id
  accepter_vpc_id        = module.data_vpc.vpc_id
  requester_cidr         = local.app_vpc_cidr
  accepter_cidr          = local.data_vpc_cidr
  app_route_table_ids    = module.app_vpc.all_route_table_ids
  data_route_table_ids   = module.data_vpc.all_route_table_ids
  app_route_table_count  = 2
  data_route_table_count = 2

  depends_on = [module.app_vpc, module.data_vpc]
}

###############################################################################
# Monitoring VPC (us-west-2) - DR
###############################################################################
module "monitoring_vpc" {
  source    = "./modules/vpc"
  providers = { aws = aws.secondary }

  resource_prefix = "${local.prefix}-mon"
  vpc_cidr        = local.mon_vpc_cidr
  region          = var.aws_region_secondary

  subnets = [
    { name = "${local.prefix}-mon-private-2a", type = "private", cidr = "10.30.1.0/24", az = "us-west-2a" },
    { name = "${local.prefix}-mon-private-2b", type = "private", cidr = "10.30.2.0/24", az = "us-west-2b" },
  ]
}

###############################################################################
# Transit Gateway: Cross-Region
###############################################################################
module "tgw_primary" {
  source    = "./modules/transit-gateway"
  providers = { aws = aws.primary }

  resource_prefix   = local.prefix
  vpc_id            = module.app_vpc.vpc_id
  subnet_ids        = module.app_vpc.private_subnet_ids
  vpc_cidr          = local.app_vpc_cidr
  peer_vpc_cidrs    = [local.mon_vpc_cidr]
  route_table_ids   = module.app_vpc.all_route_table_ids
  route_table_count = 2

  depends_on = [module.app_vpc]
}

module "tgw_secondary" {
  source    = "./modules/transit-gateway-peer"
  providers = { aws = aws.secondary }

  resource_prefix   = local.prefix
  peer_tgw_id       = module.tgw_primary.tgw_id
  peer_region       = var.aws_region_primary
  vpc_id            = module.monitoring_vpc.vpc_id
  subnet_ids        = module.monitoring_vpc.private_subnet_ids
  peer_vpc_cidrs    = [local.app_vpc_cidr, local.data_vpc_cidr]
  route_table_ids   = module.monitoring_vpc.all_route_table_ids
  route_table_count = 1

  depends_on = [module.monitoring_vpc, module.tgw_primary]
}

# BUG: TGW Peering Accepter is MISSING — peserta harus tambahkan ini
# resource "aws_ec2_transit_gateway_peering_attachment_accepter" "cross_region" {
#   provider                      = aws.primary
#   transit_gateway_attachment_id = module.tgw_secondary.peering_attachment_id
#   tags                          = { Name = "${local.prefix}-tgw-peering-accepted" }
# }

###############################################################################
# Security Groups - App VPC
###############################################################################
module "app_security_groups" {
  source    = "./modules/security-groups"
  providers = { aws = aws.primary }

  resource_prefix    = local.prefix
  vpc_id             = module.app_vpc.vpc_id
  primary_vpc_cidr   = local.app_vpc_cidr
  secondary_vpc_cidr = local.mon_vpc_cidr
}

###############################################################################
# Security Groups - Data VPC
###############################################################################
resource "aws_security_group" "data_db" {
  provider    = aws.primary
  name        = "${local.prefix}-sg-db"
  description = "Aurora PostgreSQL - allow from App VPC"
  vpc_id      = module.data_vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [local.app_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-sg-db" }
}

resource "aws_security_group" "data_cache" {
  provider    = aws.primary
  name        = "${local.prefix}-sg-cache"
  description = "ElastiCache Redis - allow from App VPC"
  vpc_id      = module.data_vpc.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [local.app_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-sg-cache" }
}

###############################################################################
# EKS Cluster (App VPC)
###############################################################################
module "eks" {
  source = "./modules/eks"
  providers = { aws = aws.primary }

  resource_prefix    = local.prefix
  vpc_id             = module.app_vpc.vpc_id
  private_subnet_ids = module.app_vpc.private_subnet_ids
  security_group_id  = module.app_security_groups.eks_sg_id
  cluster_version    = "1.31"
  node_instance_type = "t3.medium"
  node_min_size      = 2
  node_max_size      = 4
}

###############################################################################
# RDS Aurora (Data VPC)
###############################################################################
module "rds_aurora" {
  source = "./modules/rds"
  providers = { aws = aws.primary }

  resource_prefix      = local.prefix
  vpc_id               = module.data_vpc.vpc_id
  db_subnet_group_name = module.data_vpc.isolated_subnet_ids
  security_group_id    = aws_security_group.data_db.id
  master_username      = "postgres"
  allocated_storage    = 20
  db_engine_version    = "16.4"
}

###############################################################################
# ElastiCache Redis (Data VPC)
###############################################################################
module "elasticache" {
  source = "./modules/elasticache"
  providers = { aws = aws.primary }

  resource_prefix   = local.prefix
  vpc_id            = module.data_vpc.vpc_id
  subnet_ids        = module.data_vpc.isolated_subnet_ids
  security_group_id = aws_security_group.data_cache.id
  engine_version    = "7.1"
  node_type         = "cache.t3.micro"
}

###############################################################################
# ALB (App VPC)
###############################################################################
module "alb" {
  source = "./modules/alb"
  providers = { aws = aws.primary }

  resource_prefix   = local.prefix
  vpc_id            = module.app_vpc.vpc_id
  public_subnet_ids = module.app_vpc.public_subnet_ids
  security_group_id = module.app_security_groups.alb_sg_id
}

###############################################################################
# ECR
###############################################################################
module "ecr" {
  source = "./modules/ecr"
  providers = { aws = aws.primary }

  resource_prefix = local.prefix
  repositories = [
    { name = "${local.prefix}-api-app", region = var.aws_region_primary },
    { name = "${local.prefix}-fe-app",  region = var.aws_region_primary },
  ]
}

###############################################################################
# Event Processing
###############################################################################
module "event_processing" {
  source = "./modules/event-processing"
  providers = { aws = aws.primary }

  resource_prefix = local.prefix
}

###############################################################################
# Lambda
###############################################################################
module "lambda" {
  source = "./modules/lambda"
  providers = { aws = aws.primary }

  resource_prefix    = local.prefix
  kinesis_stream_arn = module.event_processing.kinesis_stream_arn
  event_bus_name     = module.event_processing.event_bus_name
}

###############################################################################
# S3
###############################################################################
module "s3" {
  source    = "./modules/s3"
  providers = { aws = aws.primary }

  resource_prefix = local.prefix
  student_name    = var.student_name
}

###############################################################################
# Monitoring ECS (us-east-1 — Grafana runs here)
###############################################################################
module "monitoring" {
  source    = "./modules/monitoring"
  providers = { aws = aws.primary }

  resource_prefix = local.prefix
  primary_region  = var.aws_region_primary
  vpc_id          = module.app_vpc.vpc_id
  subnet_ids      = module.app_vpc.private_subnet_ids
  region          = var.aws_region_primary
}

###############################################################################
# Outputs
###############################################################################
output "eks_cluster_name" { value = module.eks.cluster_name }
output "primary_vpc_id" { value = module.app_vpc.vpc_id }
output "data_vpc_id" { value = module.data_vpc.vpc_id }
output "vpc_peering_id" { value = module.vpc_peering.peering_connection_id }
output "tgw_id" { value = module.tgw_primary.tgw_id }
output "rds_endpoint" { value = module.rds_aurora.db_endpoint }
output "redis_endpoint" { value = module.elasticache.redis_endpoint }
output "alb_dns_name" { value = module.alb.alb_dns_name }
output "kinesis_stream_name" { value = module.event_processing.kinesis_stream_name }
