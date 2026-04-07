variable "aws_region" {
  description = "The AWS region to deploy into"
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g., staging, prod)"
  type        = string
}

variable "key_name" {
  description = "Name of the existing EC2 key pair for SSH access"
  type        = string
}

variable "db_password" {
  description = "Password for the RDS instance"
  type        = string
  sensitive   = true
}

variable "db_user" {
  description = "Username for the RDS instance"
  default     = "symplichain_admin"
}
