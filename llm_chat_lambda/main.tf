
# – Prompt Management –

resource "awscc_bedrock_prompt_version" "example" {
  prompt_arn  = awscc_bedrock_prompt.example.arn
  description = "example"
}

resource "awscc_bedrock_prompt" "example" {
  name                        = "example"
  description                 = "example"
  default_variant             = "variant-example"

  variants = [
    {
      name          = "variant-example"
      template_type = "TEXT"
      template_configuration = {
        text = {
          input_variables = [
            {
              name = "topic"
            }
          ]
          text = "Make me a {{genre}} playlist consisting of the following number of songs: {{number}}."
        }
      }
    }

  ]

}

# Read the prompt text from a file
data "local_file" "prompt_text" {
  filename = "${path.module}/prompts/prompt.txt"
}

# Archive the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Create IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name               = "${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Attach policies to the Lambda role
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.lambda_name}-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions = [
      "bedrock-runtime:InvokeAgent",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

# Create Lambda function
resource "aws_lambda_function" "lambda" {
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.9"
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BEARER_TOKEN      = var.bearer_token
      AGENT_ID          = var.agent_id
      AGENT_ALIAS_ID    = var.agent_alias_id
      PROMPT_IDENTIFIER = awscc_bedrock_prompt.example.name
      PROMPT_VERSION    = "latest"
    }
  }
}

# Create HTTPS endpoint for the Lambda function
resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.lambda.function_name
  authorization_type = "NONE"
}

output "lambda_function_url" {
  value       = aws_lambda_function_url.lambda_url.function_url
  description = "URL of the Lambda function"
}

output "prompt_name" {
  value       = awscc_bedrock_prompt.example.name
  description = "The name of the Bedrock prompt created"
}