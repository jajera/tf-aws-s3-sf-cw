variable "use_case" {
  default = "tf-aws-s3-sf-cw"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_resourcegroups_group" "rg" {
  name        = "example-${random_string.suffix.result}"
  description = "Resource Group for ${var.use_case}"

  resource_query {
    query = <<JSON
    {
      "ResourceTypeFilters": [
        "AWS::AllSupported"
      ],
      "TagFilters": [
        {
          "Key": "UseCase",
          "Values": [
            "${var.use_case}"
          ]
        }
      ]
    }
    JSON
  }

  tags = {
    Name    = "tf-rg-example"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_s3_bucket" "example" {
  bucket        = "example-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name    = "tf-s3-bucket-example"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.example.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "example" {
  depends_on = [aws_s3_bucket_ownership_controls.example]

  bucket = aws_s3_bucket.example.id
  acl    = "private"
}

resource "aws_s3_bucket_notification" "example" {
  bucket      = aws_s3_bucket.example.id
  eventbridge = true
}

data "template_file" "example" {
  template = file("${path.module}/external/lambda/lambda_function.py")
}

data "archive_file" "example" {
  type        = "zip"
  output_path = "${path.module}/external/lambda/lambda_function.zip"

  source {
    content  = data.template_file.example.rendered
    filename = "lambda_function.py"
  }
}

resource "aws_sfn_state_machine" "example" {
  name = "example-${random_string.suffix.result}"
  role_arn   = aws_iam_role.step_function.arn
  definition = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "Lambda Invoke",
  "States": {
    "Lambda Invoke": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "OutputPath": "$.Payload",
      "Parameters": {
        "Payload.$": "$",
        "FunctionName": "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:example-${random_string.suffix.result}:$LATEST"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "End": true
    }
  }
}
EOF

  tags = {
    Name    = "tf-sfn-machine-example"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_iam_role" "step_function" {
  name = "example-${random_string.suffix.result}-step_function"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "lambda_invoke" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:example-${random_string.suffix.result}:*"
    ]
  }
}

resource "aws_iam_policy" "lambda_invoke" {
  name   = "example-${random_string.suffix.result}-lambda_invoke"
  policy = data.aws_iam_policy_document.lambda_invoke.json
}

resource "aws_iam_role_policy_attachment" "lambda_invoke" {
  role       = aws_iam_role.step_function.name
  policy_arn = aws_iam_policy.lambda_invoke.arn
}

data "aws_iam_policy_document" "xray_access" {
  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "xray_access" {
  name   = "example-${random_string.suffix.result}-xray_access"
  policy = data.aws_iam_policy_document.xray_access.json
}

resource "aws_iam_role_policy_attachment" "xray_access" {
  role       = aws_iam_role.step_function.name
  policy_arn = aws_iam_policy.xray_access.arn
}

resource "aws_iam_role" "lambda" {
  name = "example-${random_string.suffix.result}-lambda"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "lambda_basic_execute" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/mytest2:example-${random_string.suffix.result}-lambda"
    ]
  }
}

resource "aws_iam_policy" "lambda_basic_execute" {
  name   = "example-${random_string.suffix.result}-lambda_basic_execute"
  policy = data.aws_iam_policy_document.lambda_basic_execute.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execute" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_basic_execute.arn
}

resource "aws_lambda_function" "example" {
  function_name    = "example-${random_string.suffix.result}"
  filename         = "${path.module}/external/lambda/lambda_function.zip"
  handler          = "lambda_function.lambda_handler"
  publish          = true
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.11"
  source_code_hash = data.archive_file.example.output_base64sha256

  tags = {
    Name    = "tf-lambda-example"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}

resource "aws_cloudwatch_event_rule" "example" {
  name        = "example-${random_string.suffix.result}"

  event_pattern = jsonencode({
    detail-type = [
      "Object Created"
    ],
    source = [
      "aws.s3"
    ]
  })

  tags = {
    Name    = "tf-cw_event_rule-example"
    Owner   = "John Ajera"
    UseCase = var.use_case
  }
}


resource "aws_iam_role" "eventbridge" {
  name = "example-${random_string.suffix.result}-eventbridge"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "eventbridge_invoke" {
  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution"
    ]
    resources = [
      "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:example-${random_string.suffix.result}"
    ]
  }
}

resource "aws_iam_policy" "eventbridge_invoke" {
  name   = "example-${random_string.suffix.result}-eventbridge_invoke"
  policy = data.aws_iam_policy_document.eventbridge_invoke.json
}

resource "aws_iam_role_policy_attachment" "eventbridge_invoke" {
  role       = aws_iam_role.eventbridge.name
  policy_arn = aws_iam_policy.eventbridge_invoke.arn
}

resource "aws_cloudwatch_event_target" "example" {
  rule      = aws_cloudwatch_event_rule.example.name
  target_id = "SendToStepFunction"
  arn       = aws_sfn_state_machine.example.arn
  role_arn  = aws_iam_role.eventbridge.arn
}
