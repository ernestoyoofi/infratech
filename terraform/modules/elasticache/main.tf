terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "engine_version" { type = string }
variable "node_type" { type = string }

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.resource_prefix}-redis-subnet"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.resource_prefix}-redis"
  engine               = "memcached"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.security_group_id]
  tags                 = { Name = "${var.resource_prefix}-redis" }
}

output "redis_endpoint" { value = aws_elasticache_cluster.main.cache_nodes[0].address }
output "redis_port" { value = aws_elasticache_cluster.main.port }
