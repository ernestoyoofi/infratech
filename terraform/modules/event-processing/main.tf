terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }

resource "aws_kinesis_stream" "main" {
  name             = "${var.resource_prefix}-event-stream"
  shard_count      = 1
  retention_period = 168
  tags             = { Name = "${var.resource_prefix}-event-stream" }
}

resource "aws_cloudwatch_event_bus" "main" {
  name = "${var.resource_prefix}-saas-events"
  tags = { Name = "${var.resource_prefix}-saas-events" }
}

resource "aws_dynamodb_table" "audit" {
  name         = "${var.resource_prefix}-audit-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${var.resource_prefix}-audit-log" }
}

resource "aws_sns_topic" "user_events" {
  name = "${var.resource_prefix}-user-events"
  tags = { Name = "${var.resource_prefix}-user-events" }
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.resource_prefix}-dlq"
  tags = { Name = "${var.resource_prefix}-dlq" }
}

resource "aws_sqs_queue" "events" {
  name = "${var.resource_prefix}-event-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.resource_prefix}-event-queue" }
}

output "kinesis_stream_arn" { value = aws_kinesis_stream.main.arn }
output "kinesis_stream_name" { value = aws_kinesis_stream.main.name }
output "event_bus_name" { value = aws_cloudwatch_event_bus.main.name }
output "sns_topic_arn" { value = aws_sns_topic.user_events.arn }
output "sqs_queue_arn" { value = aws_sqs_queue.events.arn }
