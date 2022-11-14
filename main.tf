provider "aws" {
  region = "us-east-1"
}

resource "aws_cloudwatch_log_group" "this" {
  name = "/aws/exposure-logs"

  tags = var.tags
}

resource "aws_sns_topic" "this" {
  name = "exposure-notifications"
}

module "eventbridge" {
  source = "terraform-aws-modules/eventbridge/aws"

  create_bus = false

  rules = {
    exposure = {
      description = "Capture exposure health events"
      event_pattern = jsonencode({
        "source" : ["aws.health"],
        "detail-type" : ["AWS Health Event"],
        "detail" : {
          "service" : ["RISK"],
          "eventTypeCategory" : ["issue"]
        }
      })
      enabled = true
    }
  }

  targets = {
    exposure = [
      {
        name = "send-exposures-to-sns"
        arn  = aws_sns_topic.this.arn
      },
      {
        name = "log-exposures-to-cloudwatch"
        arn  = aws_cloudwatch_log_group.this.arn
      }
    ]
  }

  tags = var.tags
}

resource "aws_iam_user" "exposure_test_account" {
  count = var.test_account ? 1 : 0
  name = "exposure_test_account"
}

resource "aws_iam_access_key" "exposure_test_account" {
  count = var.test_account ? 1 : 0
  user = aws_iam_user.exposure_test_account[0].name
}

resource "local_file" "exposure_test_account" {
  count = var.test_account ? 1 : 0
  content = jsonencode({
    name = aws_iam_user.exposure_test_account[0].name
    access_key_id = aws_iam_access_key.exposure_test_account[0].id
    secret_access_key = aws_iam_access_key.exposure_test_account[0].secret
  })
  filename = "exposure_test_account.json"
}