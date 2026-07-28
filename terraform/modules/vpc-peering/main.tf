terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "requester_vpc_id" { type = string }
variable "accepter_vpc_id" { type = string }
variable "requester_cidr" { type = string }
variable "accepter_cidr" { type = string }
variable "app_route_table_ids" { type = list(string) }
variable "data_route_table_ids" { type = list(string) }
variable "app_route_table_count" {
  type    = number
  default = 2
}
variable "data_route_table_count" {
  type    = number
  default = 2
}

resource "aws_vpc_peering_connection" "app_to_data" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  auto_accept = true

  # BUG: DNS resolution not enabled (peserta harus tambah accepter/requester blocks)
  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = {
    Name = "${var.resource_prefix}-peering-app-data"
  }
}

# MISSING ?: Routes for App VPC -> Data VPC (peserta must create these)
# Hint: use aws_route resources with count = var.app_route_table_count

resource "aws_route" "vpc_app_to_vpc_data" {
  count = var.app_route_table_count
  route_table_id = var.app_route_table_ids[var.app_route_table_count]
  destination_cidr_block = var.requester_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_to_data.id
}

# MISSING: Routes for Data VPC -> App VPC (peserta must create these)

resource "aws_route" "vpc_data_to_vpc_app" {
  count = var.app_route_table_count
  route_table_id = var.data_route_table_ids[var.data_route_table_count]
  destination_cidr_block = var.accepter_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.app_to_data.id
}

output "peering_connection_id" {
  value = aws_vpc_peering_connection.app_to_data.id
}
