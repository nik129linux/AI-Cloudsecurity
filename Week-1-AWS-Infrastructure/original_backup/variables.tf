# ---------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------

variable "aws_region" {
  description = "AWS Region where resources will be deployed"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format of 'us-east-1'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name prefix for consistent resource naming"
  type        = string
  default     = "nico-lab"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC network"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "instance_type" {
  description = "EC2 instance type for web server"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t3.large"], var.instance_type)
    error_message = "Instance type must be a supported t3 instance type."
  }
}

# --- SECURITY CONTROLS ---
variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to access via SSH. For production, restrict to VPN/Corporate IPs only"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Only for demo/lab use

  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All SSH CIDRs must be valid CIDR blocks."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for EC2 instances"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

# --- GOVERNANCE ---
variable "common_tags" {
  description = "Common tags to apply to all resources for cost allocation and governance"
  type        = map(string)
  default = {
    Owner       = "nico-security"
    Environment = "development"
    ManagedBy   = "terraform"
    Project     = "infrastructure-lab"
  }
}