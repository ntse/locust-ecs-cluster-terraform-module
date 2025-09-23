# Locust Cluster Terraform Module

This module provisions a distributed [Locust](https://locust.io/) cluster on AWS using EC2 instances. It creates the networking guard rails, IAM permissions, EC2 leader/worker nodes, and bootstrap logic required to run Locust with an opinionated but configurable setup. Consumers can point the module at their own Locust assets and tune instance types, scaling, and automation behaviour through variables exposed in `variables.tf`.

## Features

- IAM role and instance profile tailored for the Locust hosts.
- Security group opening SSH and Locust web ports, with CIDR allow-lists you control.
- TLS key pair generation with optional key export to your local machine.
- Leader and worker EC2 instances that install the requested Python runtime and Locust version via user data.
- Optional automatic start-up script that joins all workers to the leader once provisioning finishes.
- Helper outputs, including ready-to-run `scp` commands for refreshing data files on all nodes.

## Requirements

- Terraform `>= 1.5.7`.
- AWS provider `>= 6.0` (tested with latest releases).
- Access to an existing subnet in the target VPC where the instances should live.

## Quick Start

```hcl
module "locust_cluster" {
  source = "github.com/your-org/locust-cluster-module"

  cluster_name = "locust-example"
  subnet_id    = "subnet-0123456789abcdef0"

  node_size                 = 3
  loadtest_dir_source       = "../locust"
  ssh_cidr_ingress_blocks   = ["203.0.113.10/32"]
  web_cidr_ingress_blocks   = ["203.0.113.10/32"]
  locust_plan_filename      = "locustfile.py"
  auto_start_locust         = true
  tags = {
    Project     = "load-testing"
    Environment = "staging"
  }
}
```

All input variables, their defaults, and descriptions are documented in [`variables.tf`](variables.tf). Outputs are listed in [`outputs.tf`](outputs.tf).

## Examples

- [`examples/complete`](examples/complete) – end-to-end configuration that sets up the AWS provider, auto-detects the caller IP for the web security group, and wires every module input and output. Use this as a template when integrating the module into your own stack.

## Testing with LocalStack / `tflocal`

This repository ships with a GitHub Actions workflow (`.github/workflows/tflocal.yml`) that enforces `terraform fmt`, runs `terraform validate` on the module and example, and then exercises both configurations against [LocalStack](https://localstack.cloud/) using [`tflocal`](https://github.com/localstack/terraform-local). The example is fully applied and destroyed in CI to ensure repeatability. To reproduce locally:

```bash
# Install dependencies
pip install terraform-local localstack awscli-local

# Start LocalStack in another terminal
localstack start

# Validate the module
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-2 tflocal init
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-2 tflocal validate

# Validate the self-contained example
cd examples/complete
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-2 tflocal init
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-2 tflocal validate
```

## Contributing

1. Fork and clone the repository.
2. Make your changes.
3. Run `terraform fmt -recursive` to keep formatting consistent.
4. If you modify the example, ensure `tflocal validate` still passes locally or let the GitHub workflow confirm it in CI.

Feel free to open issues or pull requests for enhancements, bug fixes, or new example scenarios.
