terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "primary_region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "region" { type = string }

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/${var.resource_prefix}/ecs/grafana"
  retention_in_days = 7
  tags              = { Name = "${var.resource_prefix}-grafana-logs" }
}

resource "aws_ecs_cluster" "monitoring" {
  name = "${var.resource_prefix}-monitoring-cluster"
  tags = { Name = "${var.resource_prefix}-monitoring-cluster" }
}

output "ecs_cluster_name" { value = aws_ecs_cluster.monitoring.name }
output "ecs_cluster_arn" { value = aws_ecs_cluster.monitoring.arn }
output "log_group_name" { value = aws_cloudwatch_log_group.grafana.name }
