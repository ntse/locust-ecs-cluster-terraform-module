# Locust Cluster Terraform Module

This module provisions a distributed [Locust](https://locust.io/) cluster on AWS using ECS on Fargate. It builds the networking guard rails, compute resources, shared storage, and asset pipeline required to run Locust with an opinionated but configurable setup. Consumers can point the module at their own Locust assets and tune worker capacity, networking, and automation behaviour through variables exposed in `variables.tf`.

Based on the work of marcosborges: https://github.com/marcosborges/terraform-aws-loadtest-distribuited

## Features

- ECS Fargate services for the Locust master (1 task) and a configurable number of workers.
- Workers run on Fargate Spot capacity by default, significantly reducing cost while keeping the master on on-demand Fargate.
- Shared EFS file system mounted via an access point so every task reads the same Locust assets.
- S3 bucket and AWS DataSync task that replicate the Locust plan (and any other uploaded assets) into EFS.
- Network Load Balancer forwarding UI (8080) and worker coordination traffic (5557/5558) to the master task, with CIDR-based allow lists for the web UI.

## Requirements

- Terraform `>= 1.5.7`.
- AWS provider `>= 6.0` (tested with latest releases).
- Access to an existing subnet in the target VPC where the instances should live.

## Quick Start

```hcl
module "locust_cluster" {
  source = "github.com/ntse/locust-cluster-module"

  cluster_name = "locust-example"
  vpc_id       = "vpc-0123456789abcdef0"
  private_subnet_ids = [
    "subnet-aaaabbbbcccc11111",
    "subnet-aaaabbbbcccc22222",
    "subnet-aaaabbbbcccc33333"
  ]
  public_subnet_ids = [
    "subnet-ddddeeeeffff44444",
    "subnet-ddddeeeeffff55555"
  ]

  worker_count             = 3
  loadtest_dir_source      = "../locust"
  locust_plan_filename     = "locustfile.py"
  loadtest_dir_destination = "/loadtest"
  web_cidr_ingress_blocks  = ["203.0.113.10/32"]
  tags = {
    Project     = "load-testing"
    Environment = "staging"
  }
}
```

All input variables, their defaults, and descriptions are documented in [`variables.tf`](variables.tf). Outputs are listed in [`outputs.tf`](outputs.tf).

### Syncing test assets

At apply time the module uploads `locust_plan_filename` from `loadtest_dir_source` to the dedicated S3 bucket and keeps an AWS DataSync task ready to mirror S3 objects into EFS. Every Locust task mounts the EFS access point at `loadtest_dir_destination`, so new files appear in every container after the sync finishes.

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

## Examples

- [`examples/complete`](examples/complete) – end-to-end configuration that sets up the AWS provider, auto-detects the caller IP for the web security group, and wires every module input and output. You can use this as a template when integrating the module into your own stack.

## Contributing

1. Fork and clone the repository.
2. Make your changes.
3. Run `terraform fmt -recursive` to keep formatting consistent.
4. If you modify the example, ensure `tflocal validate` still passes locally or let the GitHub workflow confirm it in CI.

Feel free to open issues or pull requests for enhancements, bug fixes, or new example scenarios.
