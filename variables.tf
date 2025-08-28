variable "account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "304106858709"
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "stack_suffix" {
  description = "Suffix for resource names"
  type        = string
  default     = "Stg"
}

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
  default     = "vpc-0535b0782e7e4f53f"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Neptune"
  type        = list(string)
  default     = ["subnet-022b577781de0d370", "subnet-0b00553ede728b591", "subnet-081ab06bcbd8f12ee"]
}
