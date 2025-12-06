variable "aws_region" {
  description = "AWS Region where resources will be deployed (e.g., us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for consistent resource naming"
  type        = string
  default     = "Nico-Lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
}

# --- SECURITY CONTROLS ---
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to access via SSH. WARNING: 0.0.0.0/0 is for Lab use only. In Prod, restrict to VPN/Corporate IP."
  type        = string
  default     = "0.0.0.0/0"
}

# --- GOVERNANCE ---
variable "common_tags" {
  description = "Common tags to apply to all resources for cost allocation and governance"
  type        = map(string)
  default     = {
    Owner       = "Nico-Security"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
