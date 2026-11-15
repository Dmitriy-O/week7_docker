variable "aws_region" {
  description = "AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile"
  type        = string
  default     = "terraform_lab_user"
}

variable "project_name" {
  description = "Name prefix for lab resources"
  type        = string
  default     = "week10-kubernetes-hard-way"
}
