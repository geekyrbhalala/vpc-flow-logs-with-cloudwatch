terraform {
  backend "s3" {
    bucket  = "terraform-state-geekyrbhalala"
    key     = "vpc-flow-logs-with-cloudwatch/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}