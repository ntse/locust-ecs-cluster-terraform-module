variable "aws_region" {
  description = "AWS region to deploy the example cluster into"
  type        = string
  default     = "eu-west-2"
}

variable "cluster_name" {
  description = "Prefix used for naming infrastructure resources in the example"
  type        = string
  default     = "locust-example"
}

variable "node_size" {
  description = "Number of Locust worker nodes to provision"
  type        = number
  default     = 3
}

variable "loadtest_dir_source" {
  description = "Path to the directory containing Locust assets to copy to the instances"
  type        = string
  default     = "../../locust"
}

variable "locust_plan_filename" {
  description = "Filename of the Locust test plan"
  type        = string
  default     = "locustfile.py"
}

variable "loadtest_dir_destination" {
  description = "Destination directory on instances for the load test assets"
  type        = string
  default     = "/loadtest"
}

variable "ssh_user" {
  description = "SSH username for connecting to EC2 instances"
  type        = string
  default     = "ec2-user"
}

variable "ssh_export_pem" {
  description = "Export the generated private SSH key to disk"
  type        = bool
  default     = false
}

variable "leader_instance_type" {
  description = "Instance type for the Locust leader"
  type        = string
  default     = "c5n.large"
}

variable "worker_instance_type" {
  description = "Instance type for the Locust workers"
  type        = string
  default     = "c5n.xlarge"
}

variable "leader_ami_id" {
  description = "Optional override for the leader AMI"
  type        = string
  default     = ""
}

variable "worker_ami_id" {
  description = "Optional override for the worker AMI"
  type        = string
  default     = ""
}

variable "leader_associate_public_ip" {
  description = "Whether to associate a public IP address with the leader"
  type        = bool
  default     = true
}

variable "worker_associate_public_ip" {
  description = "Whether to associate public IP addresses with workers"
  type        = bool
  default     = true
}

variable "leader_monitoring" {
  description = "Enable detailed monitoring for the leader"
  type        = bool
  default     = true
}

variable "worker_monitoring" {
  description = "Enable detailed monitoring for the workers"
  type        = bool
  default     = true
}

variable "locust_version" {
  description = "Locust version to install on the cluster"
  type        = string
  default     = "2.40.5"
}

variable "python_version" {
  description = "Python version to install (major.minor[.patch])"
  type        = string
  default     = "3.13.0"
}

variable "ssh_cidr_ingress_blocks" {
  description = "CIDR blocks allowed to connect over SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "web_cidr_ingress_blocks" {
  description = "CIDR blocks allowed to connect to the Locust web UI"
  type        = list(string)
  default     = []
}

variable "vpc_cidr_block" {
  description = "CIDR block for the example VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the example public subnet"
  type        = string
  default     = "10.10.0.0/24"
}

variable "public_subnet_az" {
  description = "Availability zone for the example public subnet"
  type        = string
  default     = "eu-west-2a"
}

variable "split_data_mass_between_nodes" {
  description = "Configuration for splitting data files across workers"
  type = object({
    enable              = bool
    data_mass_filenames = list(string)
  })
  default = {
    enable              = false
    data_mass_filenames = []
  }
}

variable "auto_start_locust" {
  description = "Automatically start the Locust master and workers after provisioning"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "locust"
    Environment = "example"
  }
}

variable "leader_tags" {
  description = "Additional tags for the leader instance"
  type        = map(string)
  default = {
    Role = "locust-leader"
  }
}

variable "worker_tags" {
  description = "Additional tags for the worker instances"
  type        = map(string)
  default = {
    Role = "locust-worker"
  }
}
