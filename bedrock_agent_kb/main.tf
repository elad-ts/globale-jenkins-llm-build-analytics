terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.48"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "= 2.2.0"
    }
  }
  required_version = "~> 1.5"
}

# Use data sources to get common information about the environment
data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}

data "aws_bedrock_foundation_model" "agent" {
  model_id = var.agent_model_id
}

data "aws_bedrock_foundation_model" "kb" {
  model_id = var.kb_model_id
}

data "aws_iam_policy" "lambda_basic_execution" {
  name = "AWSLambdaBasicExecutionRole"
}

data "archive_file" "jenkins_agent_zip" {
  type             = "zip"
  source_file      = "${path.module}/lambda/jenkins_agent/index.py"
  output_path      = "${path.module}/tmp/jenkins_agent.zip"
  output_file_mode = "0666"
}

locals {
  account_id            = data.aws_caller_identity.this.account_id
  partition             = data.aws_partition.this.partition
  region                = data.aws_region.this.name
  region_name_tokenized = split("-", local.region)
  region_short          = "${substr(local.region_name_tokenized[0], 0, 2)}${substr(local.region_name_tokenized[1], 0, 1)}${local.region_name_tokenized[2]}"
}

# Knowledge base resource role
resource "aws_iam_role" "bedrock_kb_jenkins_kb" {
  name = "AmazonBedrockExecutionRoleForKnowledgeBase_${var.kb_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_jenkins_kb_model" {
  name = "AmazonBedrockFoundationModelPolicyForKnowledgeBase_${var.kb_name}"
  role = aws_iam_role.bedrock_kb_jenkins_kb.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = data.aws_bedrock_foundation_model.kb.model_arn
      }
    ]
  })
}

# S3 bucket for the knowledge base
resource "aws_s3_bucket" "jenkins_kb" {
  bucket        = "${var.kb_s3_bucket_name_prefix}-${local.region_short}-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "jenkins_kb" {
  bucket = aws_s3_bucket.jenkins_kb.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "jenkins_kb" {
  bucket = aws_s3_bucket.jenkins_kb.id
  versioning_configuration {
    status = "Enabled"
  }
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.jenkins_kb]
}

resource "aws_iam_role_policy" "bedrock_kb_jenkins_kb_s3" {
  name = "AmazonBedrockS3PolicyForKnowledgeBase_${var.kb_name}"
  role = aws_iam_role.bedrock_kb_jenkins_kb.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ListBucketStatement"
        Action   = "s3:ListBucket"
        Effect   = "Allow"
        Resource = aws_s3_bucket.jenkins_kb.arn
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = local.account_id
          }
      } },
      {
        Sid      = "S3GetObjectStatement"
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.jenkins_kb.arn}/*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = local.account_id
          }
        }
      }
    ]
  })
}

resource "aws_opensearchserverless_access_policy" "jenkins_kb" {
  name = var.kb_oss_collection_name
  type = "data"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "index"
          Resource = [
            "index/${var.kb_oss_collection_name}/*"
          ]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex", # Required for Terraform
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:UpdateIndex",
            "aoss:WriteDocument"
          ]
        },
        {
          ResourceType = "collection"
          Resource = [
            "collection/${var.kb_oss_collection_name}"
          ]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DescribeCollectionItems",
            "aoss:UpdateCollectionItems"
          ]
        }
      ],
      Principal = [
        aws_iam_role.bedrock_kb_jenkins_kb.arn,
        data.aws_caller_identity.this.arn
      ]
    }
  ])
}

resource "aws_opensearchserverless_security_policy" "jenkins_kb_encryption" {
  name = var.kb_oss_collection_name
  type = "encryption"
  policy = jsonencode({
    Rules = [
      {
        Resource = [
          "collection/${var.kb_oss_collection_name}"
        ]
        ResourceType = "collection"
      }
    ],
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "jenkins_kb_network" {
  name = var.kb_oss_collection_name
  type = "network"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${var.kb_oss_collection_name}"
          ]
        },
        {
          ResourceType = "dashboard"
          Resource = [
            "collection/${var.kb_oss_collection_name}"
          ]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_collection" "jenkins_kb" {
  name = var.kb_oss_collection_name
  type = "VECTORSEARCH"
  depends_on = [
    aws_opensearchserverless_access_policy.jenkins_kb,
    aws_opensearchserverless_security_policy.jenkins_kb_encryption,
    aws_opensearchserverless_security_policy.jenkins_kb_network
  ]
}

resource "aws_iam_role_policy" "bedrock_kb_jenkins_kb_oss" {
  name = "AmazonBedrockOSSPolicyForKnowledgeBase_${var.kb_name}"
  role = aws_iam_role.bedrock_kb_jenkins_kb.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "aoss:APIAccessAll"
        Effect   = "Allow"
        Resource = aws_opensearchserverless_collection.jenkins_kb.arn
      }
    ]
  })
}

provider "opensearch" {
  url         = aws_opensearchserverless_collection.jenkins_kb.collection_endpoint
  healthcheck = false
}

resource "opensearch_index" "jenkins_kb" {
  name                           = "bedrock-knowledge-base-default-index"
  number_of_shards               = "2"
  number_of_replicas             = "0"
  index_knn                      = true
  index_knn_algo_param_ef_search = "512"
  mappings                       = <<-EOF
    {
      "properties": {
        "bedrock-knowledge-base-default-vector": {
          "type": "knn_vector",
          "dimension": 1536,
          "method": {
            "name": "hnsw",
            "engine": "faiss",
            "parameters": {
              "m": 16,
              "ef_construction": 512
            },
            "space_type": "l2"
          }
        },
        "AMAZON_BEDROCK_METADATA": {
          "type": "text",
          "index": "false"
        },
        "AMAZON_BEDROCK_TEXT_CHUNK": {
          "type": "text",
          "index": "true"
        }
      }
    }
  EOF
  force_destroy                  = true
  depends_on                     = [aws_opensearchserverless_collection.jenkins_kb]
}

resource "time_sleep" "aws_iam_role_policy_bedrock_kb_jenkins_kb_oss" {
  create_duration = "20s"
  depends_on      = [aws_iam_role_policy.bedrock_kb_jenkins_kb_oss]
}

resource "aws_bedrockagent_knowledge_base" "jenkins_kb" {
  name     = var.kb_name
  role_arn = aws_iam_role.bedrock_kb_jenkins_kb.arn
  knowledge_base_configuration {
    vector_knowledge_base_configuration {
      embedding_model_arn = data.aws_bedrock_foundation_model.kb.model_arn
    }
    type = "VECTOR"
  }
  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.jenkins_kb.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
  depends_on = [
    aws_iam_role_policy.bedrock_kb_jenkins_kb_model,
    aws_iam_role_policy.bedrock_kb_jenkins_kb_s3,
    opensearch_index.jenkins_kb,
    time_sleep.aws_iam_role_policy_bedrock_kb_jenkins_kb_oss
  ]
}

resource "aws_bedrockagent_data_source" "jenkins_kb" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.jenkins_kb.id
  name              = "${var.kb_name}DataSource"
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.jenkins_kb.arn
    }
  }
}

# Agent resource role
resource "aws_iam_role" "bedrock_agent_jenkins_asst" {
  name = "AmazonBedrockExecutionRoleForAgents_${var.agent_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:agent/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_agent_jenkins_asst_model" {
  name = "AmazonBedrockAgentBedrockFoundationModelPolicy_${var.agent_name}"
  role = aws_iam_role.bedrock_agent_jenkins_asst.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = data.aws_bedrock_foundation_model.agent.model_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_agent_jenkins_asst_kb" {
  name = "AmazonBedrockAgentBedrockKnowledgeBasePolicy_${var.agent_name}"
  role = aws_iam_role.bedrock_agent_jenkins_asst.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "bedrock:Retrieve"
        Effect   = "Allow"
        Resource = aws_bedrockagent_knowledge_base.jenkins_kb.arn
      }
    ]
  })
}


# Action group Lambda execution role
resource "aws_iam_role" "lambda_jenkins_agent" {
  name = "FunctionExecutionRoleForLambda_${var.action_group_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "${local.account_id}"
          }
        }
      }
    ]
  })
  managed_policy_arns = [data.aws_iam_policy.lambda_basic_execution.arn]
}

# Action group Lambda function
resource "aws_lambda_function" "jenkins_agent" {
  function_name = var.action_group_name
  role          = aws_iam_role.lambda_jenkins_agent.arn
  description   = "A Lambda function for the action group ${var.action_group_name}"
  filename      = data.archive_file.jenkins_agent_zip.output_path
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  # source_code_hash is required to detect changes to Lambda code/zip
  source_code_hash = data.archive_file.jenkins_agent_zip.output_base64sha256
  depends_on       = [aws_iam_role.lambda_jenkins_agent]
}


resource "aws_lambda_permission" "jenkins_agent" {
  action         = "lambda:invokeFunction"
  function_name  = aws_lambda_function.jenkins_agent.function_name
  principal      = "bedrock.amazonaws.com"
  source_account = local.account_id
  source_arn     = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:agent/*"
}

resource "aws_bedrockagent_agent" "jenkins_asst" {
  agent_name              = var.agent_name
  agent_resource_role_arn = aws_iam_role.bedrock_agent_jenkins_asst.arn
  description             = var.agent_desc
  idle_session_ttl_in_seconds = 3600 # Must be refactored to use bedrock agent memory capabilities (https://github.com/hashicorp/terraform-provider-aws/issues/39626)
  foundation_model        = data.aws_bedrock_foundation_model.agent.model_id
  instruction             = file("${path.module}/prompt_templates/instruction.txt")
  depends_on = [
    aws_iam_role_policy.bedrock_agent_jenkins_asst_kb,
    aws_iam_role_policy.bedrock_agent_jenkins_asst_model
  ]
}

resource "aws_bedrockagent_agent_action_group" "jenkins_agent" {
  action_group_name          = var.action_group_name
  agent_id                   = aws_bedrockagent_agent.jenkins_asst.id
  agent_version              = "DRAFT"
  description                = var.action_group_desc
  skip_resource_in_use_check = true
  action_group_executor {
    lambda = aws_lambda_function.jenkins_agent.arn
  }
  api_schema {
    payload = file("${path.module}/lambda/jenkins_agent/schema.yaml")
  }
}

resource "aws_bedrockagent_agent_knowledge_base_association" "jenkins_kb" {
  agent_id             = aws_bedrockagent_agent.jenkins_asst.id
  description          = file("${path.module}/prompt_templates/kb_instruction.txt")
  knowledge_base_id    = aws_bedrockagent_knowledge_base.jenkins_kb.id
  knowledge_base_state = "ENABLED"
}

# null_resource.jenkins_asst_prepare (local-exec): }
# null_resource.jenkins_asst_prepare: Creation complete after 2s [id=6226627807937065993]
# ╷
# │ Warning: Argument is deprecated
# │
# │   with aws_iam_role.lambda_jenkins_agent,
# │   on main.tf line 409, in resource "aws_iam_role" "lambda_jenkins_agent":
# │  409:   managed_policy_arns = [data.aws_iam_policy.lambda_basic_execution.arn]
# │
# │ The managed_policy_arns argument is deprecated. Use the aws_iam_role_policy_attachment resource instead. If Terraform should exclusively manage all managed policy
# │ attachments (the current behavior of this argument), use the aws_iam_role_policy_attachments_exclusive resource as well.
# ╵
# ╷
# │ Error: preparing Agent
# │
# │   with aws_bedrockagent_agent_knowledge_base_association.jenkins_kb,
# │   on main.tf line 460, in resource "aws_bedrockagent_agent_knowledge_base_association" "jenkins_kb":
# │  460: resource "aws_bedrockagent_agent_knowledge_base_association" "jenkins_kb" {
# │
# │ preparing Bedrock Agent (21TCGSZPZJ): operation error Bedrock Agent: PrepareAgent, https response error StatusCode: 400, RequestID:
# │ 89f4aa2e-b5c8-4994-bfd4-15f9a82187da, ValidationException: Prepare operation can't be performed on Agent when it is in Preparing state. Retry the request when the agent
# │ is in a valid state.

resource "null_resource" "jenkins_asst_prepare" {
  triggers = {
    jenkins_agent_state = sha256(jsonencode(aws_bedrockagent_agent_action_group.jenkins_agent))
    jenkins_kb_state  = sha256(jsonencode(aws_bedrockagent_knowledge_base.jenkins_kb))
  }
  provisioner "local-exec" {
    command = "aws bedrock-agent prepare-agent --agent-id ${aws_bedrockagent_agent.jenkins_asst.id}"
  }
  depends_on = [
    aws_bedrockagent_agent.jenkins_asst,
    aws_bedrockagent_agent_action_group.jenkins_agent,
    aws_bedrockagent_knowledge_base.jenkins_kb
  ]
}
