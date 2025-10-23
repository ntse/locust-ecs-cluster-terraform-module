terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "http" "caller_ip" {
  url = "https://icanhazip.com"
}

locals {
  default_web_cidr = "${chomp(data.http.caller_ip.response_body)}/32"
  web_cidr_ingress = length(var.web_cidr_ingress_blocks) > 0 ? var.web_cidr_ingress_blocks : [local.default_web_cidr]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "example-locust"
  cidr = "10.129.0.0/16"

  azs             = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  private_subnets = ["10.129.1.0/24", "10.129.2.0/24", "10.129.3.0/24"]
  public_subnets  = ["10.129.101.0/24", "10.129.102.0/24", "10.129.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = var.tags
}

module "locust_cluster" {
  source = "../.."

  cluster_name               = var.cluster_name
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnets
  public_subnet_ids          = module.vpc.public_subnets
  worker_count               = var.worker_count
  loadtest_dir_source        = var.loadtest_dir_source
  locust_plan_filename       = var.locust_plan_filename
  loadtest_dir_destination   = var.loadtest_dir_destination
  locust_version             = var.locust_version
  web_cidr_ingress_blocks    = local.web_cidr_ingress
  tags                       = var.tags
}
