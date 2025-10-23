variable "aws_region" {
  description = "AWS region to deploy the example cluster into."
  type        = string
  default     = "eu-west-2"
}

variable "cluster_name" {
  description = "Prefix used for naming infrastructure resources in the example."
  type        = string
  default     = "locust-example"
}

variable "worker_count" {
  description = "Number of Locust worker tasks to run."
  type        = number
  default     = 10
}

variable "loadtest_dir_source" {
  description = "Path to the directory containing Locust assets on your machine."
  type        = string
  default     = "."
}

variable "locust_plan_filename" {
  description = "Filename of the Locust test plan inside `loadtest_dir_source`."
  type        = string
  default     = "../../locust/locustfile.py"
}

variable "loadtest_dir_destination" {
  description = "Directory where the shared EFS volume is mounted inside each task."
  type        = string
  default     = "/loadtest"
}

variable "locust_version" {
  description = "Locust Docker image tag to deploy."
  type        = string
  default     = "2.40.5"
}

variable "web_cidr_ingress_blocks" {
  description = "CIDR blocks allowed to reach the Locust web UI. Defaults to the caller IP."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all example resources."
  type        = map(string)
  default = {
    Project     = "locust"
    Environment = "example"
  }
}

variable "requirements_filename" {
  description = "Filename containing pip dependencies to install alongside the Locust plan."
  type        = string
  default     = "../../locust/requirements.txt"
}
