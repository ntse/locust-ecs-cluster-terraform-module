# Complete Example

This example provisions a full Locust cluster using the module in the repository root. It creates an isolated VPC with three public and three private subnets (with a NAT gateway), configures sensible defaults, auto-detects the caller IP to seed the web security group, and forwards all outputs from the module.

## Usage

```bash
cd examples/complete
terraform init
terraform apply
```

Override any variable defined in `variables.tf` to customise the deployment (for example, adjust worker count, CIDR blocks, or Locust versions). The example reuses the bundled `locustfile.py` by default; point `loadtest_dir_source` at your own assets if needed.
