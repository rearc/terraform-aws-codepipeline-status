locals {
  github_auth_type = var.github_app_private_key != "" ? "GitHub App" : "GitHub PAT"
  github_parameter = var.github_app_private_key != "" ? var.github_app_private_key : var.github_personal_access_token
}

resource "aws_cloudwatch_event_rule" "codepipeline_updates" {
  name        = "codepipeline-updates"
  description = "Captures CodePipeline action execution state changes."

  event_pattern = <<EOF
{
  "source": [
    "aws.codepipeline"
  ],
  "detail-type": [
    "CodePipeline Action Execution State Change"
  ],
  "detail": {
    "state": [
      "STARTED",
      "SUCCEEDED",
      "FAILED"
    ]
  }
}
EOF
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.codepipeline_status_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.codepipeline_updates.arn
}


resource "aws_cloudwatch_event_target" "codepipeline_updates" {
  target_id = "codepipeline-updates"
  rule      = aws_cloudwatch_event_rule.codepipeline_updates.name
  arn       = aws_lambda_function.codepipeline_status_reporter.arn
}

data "archive_file" "reporter_package" {
  type        = "zip"
  source_dir  = "${path.module}/codepipeline-status-reporter"
  output_path = "${path.module}/codepipeline-status-reporter.zip"
}

resource "null_resource" "pip_install" {
  triggers = {
    build_number = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "pip3 install -r ${path.module}/codepipeline-status-reporter/requirements.txt --platform manylinux1_x86_64 --only-binary=:all: --python-version 37 --abi cp37m -vvv -t ${path.module}/codepipeline-status-reporter-dependencies/python/lib/python3.7/site-packages"
  }
}

data "archive_file" "dependencies_package" {
  type        = "zip"
  source_dir  = "${path.module}/codepipeline-status-reporter-dependencies"
  output_path = "${path.module}/codepipeline-status-reporter-dependencies.zip"

  depends_on = [
    null_resource.pip_install,
  ]
}

resource "aws_lambda_layer_version" "lambda_layer" {
  filename            = "${path.module}/codepipeline-status-reporter-dependencies.zip"
  layer_name          = "codepipeline-status-reporter-dependencies"
  description         = "Provides pyjwt and cryptography from pip."
  compatible_runtimes = ["python3.7"]

  depends_on = [
    data.archive_file.dependencies_package,
  ]
}

resource "aws_lambda_function" "codepipeline_status_reporter" {
  filename         = "${path.module}/codepipeline-status-reporter.zip"
  function_name    = "codepipeline-status-reporter"
  role             = aws_iam_role.codepipeline_status_reporter.arn
  runtime          = "python3.7"
  source_code_hash = data.archive_file.reporter_package.output_base64sha256
  handler          = "lambda_function.handler"
  timeout          = 10
  layers           = ["${aws_lambda_layer_version.lambda_layer.arn}"]

  environment {
    variables = {
      GITHUB_AUTH_TYPE      = local.github_auth_type
      GITHUB_PARAMETER      = local.github_parameter
      GITHUB_APP_ID         = var.github_app_id
      GITHUB_APP_INSTALL_ID = var.github_app_install_id
      BRANCH_WHITELIST      = var.branch_whitelist
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.codepipeline_status_reporter,
    data.archive_file.reporter_package,
  ]
}


resource "aws_iam_role" "codepipeline_status_reporter" {
  name = "codepipeline-status-reporter"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "codepipeline_status_reporter" {
  name        = "codepipeline-status-reporter"
  path        = "/"
  description = "IAM policy for the CodePipeline status reporter Lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:*:*:*"
      ],
      "Effect": "Allow"
    },
    {
      "Action": [
        "codepipeline:GetPipelineExecution",
        "codepipeline:GetPipelineState",
        "codepipeline:GetPipeline"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "lambda:GetLayerVersion"
      ],
      "Resource": [
        "${aws_lambda_layer_version.lambda_layer.arn}"
      ],
      "Effect": "Allow"
    },
    {
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "${aws_iam_role.codepipeline_status_reporter.arn}"
      ],
      "Effect": "Allow"
    },
    {
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "${aws_iam_role.codepipeline_status_reporter.arn}"
      ],
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/${local.github_parameter}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "codepipeline_status_reporter" {
  role       = aws_iam_role.codepipeline_status_reporter.name
  policy_arn = aws_iam_policy.codepipeline_status_reporter.arn
}