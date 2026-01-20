
output "ec2_role_arn" {
  value = aws_iam_role.ec2_role.arn
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}

