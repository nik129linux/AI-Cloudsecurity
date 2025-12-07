# ---------------------------------------------------------
# IAM (Identity & Access Management)
# ---------------------------------------------------------

# IAM Role for Web Servers
data "aws_iam_policy_document" "web_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web" {
  name               = "${local.name_prefix}-web-role"
  assume_role_policy = data.aws_iam_policy_document.web_assume_role.json

  tags = {
    Name = "${local.name_prefix}-web-role"
  }
}

# Custom policy for web servers (minimal permissions)
data "aws_iam_policy_document" "web_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/${local.name_prefix}/*"
    ]
  }

  # CloudWatch permissions for logging
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/ec2/${local.name_prefix}/*"
    ]
  }
}

resource "aws_iam_role_policy" "web" {
  name   = "${local.name_prefix}-web-policy"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.web_policy.json
}

# Attach AWS managed SSM policy for patching
resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "${local.name_prefix}-web-profile"
  role = aws_iam_role.web.name

  tags = {
    Name = "${local.name_prefix}-web-profile"
  }
}

# IAM Role for Bastion Host
resource "aws_iam_role" "bastion" {
  name               = "${local.name_prefix}-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.web_assume_role.json

  tags = {
    Name = "${local.name_prefix}-bastion-role"
  }
}

# Attach read-only access for auditing (as per original requirement)
resource "aws_iam_role_policy_attachment" "bastion_readonly" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Attach SSM for session manager access
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = {
    Name = "${local.name_prefix}-bastion-profile"
  }
}