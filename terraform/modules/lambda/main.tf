terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "resource_prefix" { type = string }
variable "kinesis_stream_arn" { type = string }
variable "event_bus_name" { type = string }

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

resource "aws_lambda_function" "event_processor" {
  function_name = "${var.resource_prefix}-event-processor"
  role          = data.aws_iam_role.lab_role.arn
  handler       = "event-processor.lambda_handler"
  runtime       = "python3.9"
  timeout       = 3
  memory_size   = 128
  filename      = "${path.root}/../lambda/event-processor.zip"

  environment {
    variables = {
      AUDIT_TABLE_NAME    = "${var.resource_prefix}-audit-log"
      AWS_REGION_OVERRIDE = "us-east-1"
    }
  }

  tags = { Name = "${var.resource_prefix}-event-processor" }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn  = var.kinesis_stream_arn
  function_name     = aws_lambda_function.event_processor.arn
  starting_position = "LATEST"
  batch_size        = 100
}

output "lambda_arn" { value = aws_lambda_function.event_processor.arn }
output "lambda_name" { value = aws_lambda_function.event_processor.function_name }
