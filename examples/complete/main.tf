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
  url = "https://ifconfig.co/json"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  caller_ip_json   = jsondecode(data.http.caller_ip.body)
  default_web_cidr = "${local.caller_ip_json.ip}/32"
  web_cidr_ingress = length(var.web_cidr_ingress_blocks) > 0 ? var.web_cidr_ingress_blocks : [local.default_web_cidr]
}

resource "aws_vpc" "example" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    {
      Name = "${var.cluster_name}-vpc"
    },
    var.tags
  )
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = merge(
    {
      Name = "${var.cluster_name}-igw"
    },
    var.tags
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  tags = merge(
    {
      Name = "${var.cluster_name}-public-rt"
    },
    var.tags
  )
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.example.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_subnet_az
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.cluster_name}-public-subnet"
    },
    var.tags
  )
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

module "locust_cluster" {
  source = "../.."

  cluster_name = var.cluster_name
  subnet_id    = aws_subnet.public.id

  node_size                     = var.node_size
  loadtest_dir_source           = var.loadtest_dir_source
  locust_plan_filename          = var.locust_plan_filename
  loadtest_dir_destination      = var.loadtest_dir_destination
  ssh_user                      = var.ssh_user
  ssh_export_pem                = var.ssh_export_pem
  leader_instance_type          = var.leader_instance_type
  worker_instance_type          = var.worker_instance_type
  leader_ami_id                 = var.leader_ami_id
  worker_ami_id                 = var.worker_ami_id
  leader_associate_public_ip    = var.leader_associate_public_ip
  worker_associate_public_ip    = var.worker_associate_public_ip
  leader_monitoring             = var.leader_monitoring
  worker_monitoring             = var.worker_monitoring
  locust_version                = var.locust_version
  python_version                = var.python_version
  ssh_cidr_ingress_blocks       = var.ssh_cidr_ingress_blocks
  web_cidr_ingress_blocks       = local.web_cidr_ingress
  split_data_mass_between_nodes = var.split_data_mass_between_nodes
  auto_start_locust             = var.auto_start_locust
  tags                          = var.tags
  leader_tags                   = var.leader_tags
  worker_tags                   = var.worker_tags
}
