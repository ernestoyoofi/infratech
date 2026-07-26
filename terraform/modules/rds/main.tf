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

variable "db_subnet_group_name" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "master_username" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "db_engine_version" {
  type = string
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.resource_prefix}-db-subnet-group"
  subnet_ids = var.db_subnet_group_name

  tags = {
    Name = "${var.resource_prefix}-db-subnet-group"
  }
}

resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.resource_prefix}-aurora-cluster"
  engine             = "aurora-mysql"
  engine_version     = var.db_engine_version
  master_username    = var.master_username
  master_password    = "temporary-password-change-me"

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]

  skip_final_snapshot = true
  storage_encrypted   = true

  tags = {
    Name = "${var.resource_prefix}-aurora-cluster"
  }
}

resource "aws_rds_cluster_instance" "main" {
  count              = 2
  identifier         = "${var.resource_prefix}-aurora-instance-${count.index}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  publicly_accessible = true

  tags = {
    Name = "${var.resource_prefix}-aurora-instance-${count.index}"
  }
}

# Outputs
output "db_endpoint" {
  value = aws_rds_cluster.main.endpoint
}

output "db_reader_endpoint" {
  value = aws_rds_cluster.main.reader_endpoint
}

output "db_cluster_identifier" {
  value = aws_rds_cluster.main.cluster_identifier
}
