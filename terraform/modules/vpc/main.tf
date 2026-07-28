terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "region" {
  type = string
}

variable "subnets" {
  type = list(object({
    name = string
    type = string
    cidr = string
    az   = string
  }))
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.resource_prefix}-vpc"
  }
}

# Subnets configuration
resource "aws_subnet" "all" {
  for_each = { for subnet in var.subnets : subnet.name => subnet }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = replace(each.value.cidr, "/24", "/25")
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.type == "public" ? true : false

  tags = {
    Name = each.value.name
    Type = each.value.type
  }
}

locals {
  public_subnets   = { for k, v in aws_subnet.all : k => v if v.tags["Type"] == "public" }
  private_subnets  = { for k, v in aws_subnet.all : k => v if v.tags["Type"] == "private" }
  isolated_subnets = { for k, v in aws_subnet.all : k => v if v.tags["Type"] == "isolated" }
  has_public       = length(local.public_subnets) > 0
  first_public_id  = local.has_public ? values(local.public_subnets)[0].id : ""
}

# Internet Gateway (only if public subnets exist)
resource "aws_internet_gateway" "main" {
  count  = local.has_public ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.resource_prefix}-igw"
  }
}

# EIP for NAT (only if public subnets exist)
resource "aws_eip" "nat" {
  count  = local.has_public ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.resource_prefix}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# MISSING [!]: NAT Gateway resource (peserta must create this)
# Required: allocation_id from aws_eip.nat[0], subnet_id from first public subnet
# Tag: "${var.resource_prefix}-nat"

resource "aws_nat_gateway" "private_gateway" {
  count  = local.has_public ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = local.first_public_id

  tags = {
    Name ="${var.resource_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route tables
resource "aws_route_table" "public" {
  count  = local.has_public ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.resource_prefix}-rt-public"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.resource_prefix}-rt-private"
  }
}

resource "aws_route_table" "isolated" {
  count  = length(local.isolated_subnets) > 0 ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.resource_prefix}-rt-isolated"
  }
}

# Route table associations
resource "aws_route_table_association" "public" {
  for_each = local.has_public ? local.public_subnets : {}

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "isolated" {
  for_each = length(local.isolated_subnets) > 0 ? local.isolated_subnets : {}

  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated[0].id
}

# Routes
resource "aws_route" "public_gateway" {
  count                  = local.has_public ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

# MISSING [!]: Route for private subnets to reach internet via NAT Gateway
# peserta must create: aws_route pointing private route table to NAT gateway
# resource "aws_route" "private_nat" { ... }
resource "aws_route" "private_nat" {
  count                  = local.has_public ? 0 : 1
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.private_gateway
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [for s in local.public_subnets : s.id]
}

output "private_subnet_ids" {
  value = [for s in local.private_subnets : s.id]
}

output "isolated_subnet_ids" {
  value = [for s in local.isolated_subnets : s.id]
}

output "igw_id" {
  value = local.has_public ? aws_internet_gateway.main[0].id : ""
}

output "nat_gateway_id" {
  value = ""  # Will be populated after peserta creates NAT Gateway
}

output "all_route_table_ids" {
  value = distinct(compact(concat(
    local.has_public ? [aws_route_table.public[0].id] : [],
    [aws_route_table.private.id],
    length(local.isolated_subnets) > 0 ? [aws_route_table.isolated[0].id] : []
  )))
}
