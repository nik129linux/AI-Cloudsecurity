# outputs.tf
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID created in day4"
}

output "igw_id" {
  value       = aws_internet_gateway.igw.id
  description = "Internet Gateway ID created in day4"
}

output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "Public route table ID created in day4"
}

output "public_subnet_a_id" {
  value       = aws_subnet.public_a.id
  description = "Public subnet A ID created in day4"
}
