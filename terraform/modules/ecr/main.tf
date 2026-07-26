terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "repositories" {
  type = list(object({
    name   = string
    region = string
  }))
}

resource "aws_ecr_repository" "repos" {
  for_each = { for r in var.repositories : r.name => r }

  name                 = each.value.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = { Name = each.value.name }
}

output "repository_urls" {
  value = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
}
