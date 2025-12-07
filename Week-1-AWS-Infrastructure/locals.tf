# ---------------------------------------------------------
# LOCAL VALUES
# ---------------------------------------------------------
locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # Availability zones
  azs = ["${var.aws_region}a", "${var.aws_region}b"]

  # Network configuration
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = [cidrsubnet(local.vpc_cidr, 8, 1), cidrsubnet(local.vpc_cidr, 8, 2)]
  private_subnet_cidrs = [cidrsubnet(local.vpc_cidr, 8, 11), cidrsubnet(local.vpc_cidr, 8, 12)]
}