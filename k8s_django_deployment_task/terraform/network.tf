locals {
  aws_region   = "us-east-1"
  aws_profile  = "terraform_lab_user"
  project_name = "week8-healthchecks"
  vpc_cidr     = "10.80.0.0/16"

  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2
  )
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = local.project_name
  cidr = local.vpc_cidr
  azs  = local.availability_zones

  public_subnets = [
    cidrsubnet(local.vpc_cidr, 8, 0),
    cidrsubnet(local.vpc_cidr, 8, 1),
  ]

  private_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 1),
    cidrsubnet(local.vpc_cidr, 4, 2),
  ]

  database_subnets = [
    cidrsubnet(local.vpc_cidr, 8, 240),
    cidrsubnet(local.vpc_cidr, 8, 241),
  ]

  enable_dns_support   = true
  enable_dns_hostnames = true

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
