locals {
  vpc_id                = data.terraform_remote_state.day4.outputs.vpc_id
  public_route_table_id = data.terraform_remote_state.day4.outputs.public_route_table_id

  az_a = data.aws_availability_zones.available.names[0]
  az_b = data.aws_availability_zones.available.names[1]

  tags = {
    Project = "Roadmap90"
    Owner   = "Nico"
    Day     = "5"
  }
}

# Public subnet B only (A already exists in Day 4)
resource "aws_subnet" "public_b" {
  vpc_id                  = local.vpc_id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = local.az_b
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "nico-public-b" })
}

# Associate public_b to the Day 4 public route table (IGW route lives there)
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = local.public_route_table_id
}

# Private subnets (no public IP)
resource "aws_subnet" "private_a" {
  vpc_id                  = local.vpc_id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "nico-private-a" })
}

resource "aws_subnet" "private_b" {
  vpc_id                  = local.vpc_id
  cidr_block              = "10.0.102.0/24"
  availability_zone       = local.az_b
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "nico-private-b" })
}

# Private route table (NO internet route; no NAT today)
resource "aws_route_table" "private" {
  vpc_id = local.vpc_id
  tags   = merge(local.tags, { Name = "nico-private-rt" })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
