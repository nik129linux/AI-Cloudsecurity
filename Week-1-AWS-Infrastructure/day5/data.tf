data "terraform_remote_state" "day4" {
  backend = "s3"
  config = {
    bucket       = "tf-state-nico-lab-220197469675-1768167519"
    key          = "week1/day4/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
data "aws_availability_zones" "available" {
  state = "available"
}
