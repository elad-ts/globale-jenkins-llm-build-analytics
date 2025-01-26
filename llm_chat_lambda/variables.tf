variable "region" {
  description = "AWS region"
  type        = string
}

variable "lambda_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "prompt_name" {
  description = "Name of the Bedrock prompt"
  type        = string
}

variable "bearer_token" {
  description = "Bearer token for authentication"
  type        = string
}

variable "agent_id" {
  description = "Bedrock Agent ID"
  type        = string
}

variable "agent_alias_id" {
  description = "Bedrock Agent Alias ID (optional)"
  type        = string
  default     = ""
}

variable "create_prompt_version" {
  description = "Whether or not to create a prompt version."
  type        = bool
  default     = false
}
