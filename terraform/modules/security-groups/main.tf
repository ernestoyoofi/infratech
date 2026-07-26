terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "primary_vpc_cidr" {
  type = string
}

variable "secondary_vpc_cidr" {
  type = string
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.resource_prefix}-sg-alb"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_prefix}-sg-alb"
  }
}

resource "aws_security_group" "eks" {
  name        = "${var.resource_prefix}-sg-eks"
  description = "Security group for EKS pods"
  vpc_id      = var.vpc_id

  ingress {
    description = "API port from anywhere"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Frontend port from anywhere"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Metrics from Oregon"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  ingress {
    description = "ICMP from Oregon"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_prefix}-sg-eks"
  }
}

# Database Security Group
resource "aws_security_group" "db" {
  name        = "${var.resource_prefix}-sg-db"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_prefix}-sg-db"
  }
}

# Cache Security Group
resource "aws_security_group" "cache" {
  name        = "${var.resource_prefix}-sg-cache"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_prefix}-sg-cache"
  }
}

# Outputs
output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "eks_sg_id" {
  value = aws_security_group.eks.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}

output "cache_sg_id" {
  value = aws_security_group.cache.id
}
