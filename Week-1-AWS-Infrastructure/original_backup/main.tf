# ---------------------------------------------------------
# PROVIDER CONFIGURATION
# ---------------------------------------------------------
provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------
# NETWORKING (VPC, Subnet, IGW, Route Table)
# ---------------------------------------------------------

# 1. VPC (The Network Foundation)
resource "aws_vpc" "lab_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # Best Practice: Allows resolving public DNS names

  # Merging project specific name with common governance tags
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-VPC"
  })
}

# 2. Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true # Auto-assign Public IPs to instances in this subnet

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-Public-Subnet"
  })
}

# 3. Internet Gateway (IGW) - Enables outbound internet access
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-IGW"
  })
}

# 4. Route Table - Directs internet traffic to the IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"                # Traffic destined for the internet...
    gateway_id = aws_internet_gateway.gw.id # ...goes through the Gateway
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-PublicRT"
  })
}

# 5. Route Table Association - Links the Subnet to the Route Table
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ---------------------------------------------------------
# SECURITY (Security Groups)
# ---------------------------------------------------------

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-Web-SG"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = aws_vpc.lab_vpc.id

  # Inbound Rule: SSH (Port 22)
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr] # Controlled via variable
  }

  # Inbound Rule: HTTP (Port 80)
  ingress {
    description = "HTTP Access (Web)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to the world
  }

  # Outbound Rule (Egress) - Allow all traffic
  # Important: Without this, the instance cannot download updates (yum/apt)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-SG"
  })
}

# ---------------------------------------------------------
# IAM (Identity & Access Management)
# ---------------------------------------------------------

# 1. Trust Policy: Defines WHO can assume this role (EC2 Service)
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# 2. IAM Role: The identity used by the EC2 instance
resource "aws_iam_role" "auditor_role" {
  name               = "${var.project_name}-Audit-Role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = var.common_tags
}

# 3. Policy Attachment: Grant permissions to the Role
# Security Best Practice: Principle of Least Privilege (ReadOnly)
resource "aws_iam_role_policy_attachment" "attach_readonly" {
  role       = aws_iam_role.auditor_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 4. Instance Profile: The container to pass the Role to EC2
resource "aws_iam_instance_profile" "auditor_profile" {
  name = "${var.project_name}-InstanceProfile"
  role = aws_iam_role.auditor_role.name
}

# ---------------------------------------------------------
# COMPUTE (EC2 Instance)
# ---------------------------------------------------------

# Data Source: Automatically fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro" # Free Tier eligible (check current region specs)
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.auditor_profile.name

  # User Data: Bootstrapping script (runs only on first boot)
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install httpd -y
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello World! Deployed with Enterprise Grade Terraform 🚀</h1>" > /var/www/html/index.html
              EOF

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-Server"
  })
}

# ---------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------

output "website_url" {
  description = "Public URL to access the Web Server"
  value       = "http://${aws_instance.web_server.public_ip}"
}

output "ssh_command" {
  description = "Command to connect via SSH"
  value       = "ssh ec2-user@${aws_instance.web_server.public_ip}"
}

