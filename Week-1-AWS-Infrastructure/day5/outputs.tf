output "public_subnet_ids" {
  value = [
    data.terraform_remote_state.day4.outputs.public_subnet_a_id,
    aws_subnet.public_b.id
  ]
}

output "private_subnet_ids" {
  value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}
