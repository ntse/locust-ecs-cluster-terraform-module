variable "cluster_name" {
  description = "Prefix used when naming resources created by the module."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where all resources will be created."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the Locust ECS tasks (master and workers)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "Provide at least one subnet ID for the ECS tasks."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs where the load balancer will be deployed (must span at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "Provide at least two subnet IDs in distinct AZs for the load balancer."
  }
}

variable "worker_count" {
  description = "Desired number of Locust workers. These tasks run on Fargate Spot capacity."
  type        = number
  default     = 3
}

variable "loadtest_dir_source" {
  description = "Local directory that contains the Locust assets. The module uploads the test plan file from this folder to S3."
  type        = string
  default     = "locust"
}

variable "locust_plan_filename" {
  description = "Filename of the Locust test plan to run."
  type        = string
  default     = "locustfile.py"
}

variable "loadtest_dir_destination" {
  description = "Filesystem path mounted inside each task from the shared EFS volume."
  type        = string
  default     = "/loadtest"
}

variable "locust_version" {
  description = "Locust Docker image tag to deploy."
  type        = string
  default     = "2.40.5"
}

variable "requirements_filename" {
  description = "Filename containing pip dependencies to install alongside the Locust plan."
  type        = string
  default     = "requirements.txt"
}

variable "web_cidr_ingress_blocks" {
  description = "CIDR blocks allowed to reach the Locust web UI."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}
