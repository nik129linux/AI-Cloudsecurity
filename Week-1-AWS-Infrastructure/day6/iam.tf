locals {
  tags = {
    Project = "Roadmap90"
    Owner   = "Nico"
    Day     = "6"
  }
}

# Trust policy: allows EC2 service to assume this role
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "nico-lab-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = local.tags
}

# Least privilege example: allow SSM Session Manager (no SSH keys needed later)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile: what you attach to an EC2 instance
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "nico-lab-ec2-profile"
  role = aws_iam_role.ec2_role.name
  tags = local.tags
}
