variable "kb_s3_bucket_name_prefix" {
  description = "The name prefix of the S3 bucket for the data source of the knowledge base."
  type        = string
  default     = "jenkins-kb"
}

variable "kb_oss_collection_name" {
  description = "The name of the OSS collection for the knowledge base."
  type        = string
  default     = "bedrock-knowledge-base-jenkis-kb"
}

variable "kb_model_id" {
  description = "The ID of the foundational model used by the knowledge base."
  type        = string
  default     = "amazon.titan-embed-text-v1"
}

variable "kb_name" {
  description = "The knowledge base name."
  type        = string
  default     = "JenkinsKB"
}

variable "agent_model_id" {
  description = "The ID of the foundational model used by the agent."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "agent_name" {
  description = "The agent name."
  type        = string
  default     = "JenkinsAssistant"
}

variable "agent_desc" {
  description = "The agent description."
  type        = string
  default     = "An assistant that provides info and remediation about failed Jenkins builds."
}

variable "action_group_name" {
  description = "The action group name."
  type        = string
  default     = "JenkinsAPI"
}

variable "action_group_desc" {
  description = "The action group description."
  type        = string
  default     = "The current Jenkins jobs API."
}

