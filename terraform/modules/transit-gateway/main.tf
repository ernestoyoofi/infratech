terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_cidr" { type = string }
variable "peer_vpc_cidrs" {
  type    = list(string)
  default = []
}
variable "route_table_ids" {
  type    = list(string)
  default = []
}
variable "route_table_count" {
  type    = number
  default = 2
}

resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.resource_prefix} Transit Gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags                            = { Name = "${var.resource_prefix}-tgw-2026" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  tags               = { Name = "${var.resource_prefix}-tgw-attach-primary" }
}

# MISSING: Routes in VPC route tables pointing to remote CIDRs via TGW
# peserta must create aws_route resources for each route_table + peer_vpc_cidr combination

output "tgw_id" { value = aws_ec2_transit_gateway.main.id }
output "tgw_arn" { value = aws_ec2_transit_gateway.main.arn }
output "tgw_attachment_id" { value = aws_ec2_transit_gateway_vpc_attachment.this.id }
