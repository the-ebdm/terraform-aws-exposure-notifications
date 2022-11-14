provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name = "/aws/exposure-logs"

  tags = var.tags
}

resource "aws_sns_topic" "this" {
  name = "exposure-notifications"
}

data "aws_iam_policy_document" "sns_topic_default_policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.this.arn
    ]

    sid = "__default_statement_ID"
  }
}

data "aws_iam_policy_document" "sns_topic_eventbridge_policy" {
  policy_id = "Allow_Publish_Events"

  statement {
    actions = [
      "SNS:Publish"
    ]

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [
      aws_sns_topic.this.arn
    ]

    sid = "Allow_Publish_Events"
  }
}

data "aws_iam_policy_document" "combined" {
  source_policy_documents = [
    data.aws_iam_policy_document.sns_topic_default_policy.json,
    data.aws_iam_policy_document.sns_topic_eventbridge_policy.json
  ]
}

resource "aws_sns_topic_policy" "this" {
  arn = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.combined.json
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