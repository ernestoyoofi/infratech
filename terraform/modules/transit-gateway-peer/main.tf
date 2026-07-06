terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "peer_tgw_id" { type = string }
variable "peer_region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "peer_vpc_cidrs" { type = list(string) }
variable "route_table_ids" {
  type    = list(string)
  default = []
}
variable "route_table_count" {
  type    = number
  default = 1
}

resource "aws_ec2_transit_gateway" "secondary" {
  description                     = "${var.resource_prefix} Transit Gateway (secondary)"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags                            = { Name = "${var.resource_prefix}-tgw-secondary" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "secondary" {
  transit_gateway_id = aws_ec2_transit_gateway.secondary.id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  tags               = { Name = "${var.resource_prefix}-tgw-attach-monitoring" }
}

resource "aws_ec2_transit_gateway_peering_attachment" "cross_region" {
  transit_gateway_id      = aws_ec2_transit_gateway.secondary.id
  peer_transit_gateway_id = var.peer_tgw_id
  peer_region             = var.peer_region
  tags                    = { Name = "${var.resource_prefix}-tgw-peering-cross-region" }
}

# MISSING: Routes in monitoring VPC to reach primary region via TGW
# peserta must create aws_route for each route_table + peer_vpc_cidr

output "secondary_tgw_id" { value = aws_ec2_transit_gateway.secondary.id }
output "peering_attachment_id" { value = aws_ec2_transit_gateway_peering_attachment.cross_region.id }
