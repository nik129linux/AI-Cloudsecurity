# ---------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.web.dns_name
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = aws_lb.web.zone_id
}

output "website_url" {
  description = "URL to access the web application"
  value       = "http://${aws_lb.web.dns_name}"
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = "ssh ec2-user@${aws_instance.bastion.public_ip}"
}

output "bastion_session_manager_command" {
  description = "AWS CLI command to start Session Manager session with bastion"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id}"
}

output "web_servers_session_manager" {
  description = "Use Session Manager to connect to web servers via bastion"
  value       = "Use 'aws ssm start-session --target <instance-id>' from the bastion host"
}

output "security_groups" {
  description = "Security group IDs"
  value = {
    alb     = aws_security_group.alb.id
    web     = aws_security_group.web.id
    bastion = aws_security_group.bastion.id
  }
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.name
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.web.id
}

# Security information
output "security_improvements" {
  description = "List of security improvements implemented"
  value = [
    "✅ Web servers deployed in private subnets",
    "✅ Application Load Balancer in public subnets",
    "✅ Bastion host for secure SSH access",
    "✅ Security groups with minimal required permissions",
    "✅ EBS encryption enabled",
    "✅ IMDSv2 required on all instances",
    "✅ VPC Flow Logs enabled",
    "✅ Auto Scaling Group for high availability",
    "✅ Default security group locked down",
    "✅ Detailed monitoring enabled",
    "✅ IAM roles follow principle of least privilege",
    "✅ User data scripts with security hardening",
  ]
}