variable "aws_region" {
  description = "AWS region for the deployment"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "live_environment" {
  description = "Environment receiving production traffic"
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.live_environment)
    error_message = "Use either blue or green."
  }
}