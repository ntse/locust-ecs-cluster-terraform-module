data "aws_subnet" "selected" {
  id = var.subnet_id
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  cluster_name             = var.cluster_name
  loadtest_dir_destination = var.loadtest_dir_destination

  python_version_match = try(regexall("^(\\d+)\\.(\\d+)", var.python_version)[0], null)
  python_major         = try(local.python_version_match[1], "3")
  python_minor         = try(local.python_version_match[2], "13")
  python_package_name  = format("python%s.%s", local.python_major, local.python_minor)
  python_pip_package   = "${local.python_package_name}-pip"
  python_bin           = local.python_package_name

  node_user_data = base64encode(
    templatefile(
      "${path.module}/templates/locust-node-user-data.sh.tpl",
      {
        python_package     = local.python_package_name,
        python_pip_package = local.python_pip_package,
        python_bin         = local.python_bin,
        locust_version     = var.locust_version
      }
    )
  )

  leader_entrypoint_template = <<-EOT
    nohup locust \
      -f ${var.locust_plan_filename} \
      --web-port=8080 \
      --expect-workers=${var.node_size} \
      --master > locust-leader.out 2>&1 &
  EOT

  node_entrypoint_template = <<-EOT
    nohup locust \
      -f ${var.locust_plan_filename} \
      --worker \
      --master-host={LEADER_IP} > locust-worker.out 2>&1 &
  EOT

  leader_entrypoint = trimspace(local.leader_entrypoint_template)
  node_entrypoint   = trimspace(local.node_entrypoint_template)

  wait_for_setup_cmd      = "while [ ! -f /tmp/finished-setup ]; do echo 'waiting setup to be installed'; sleep 5; done"
  web_cidr_ingress_blocks = var.web_cidr_ingress_blocks
  export_private_key_cmd  = var.ssh_export_pem ? "echo '${tls_private_key.loadtest.private_key_pem}' > ${local.cluster_name}-keypair.pem ; chmod 600 ${local.cluster_name}-keypair.pem" : "echo 'key pair export disabled'"
  leader_ami_id           = var.leader_ami_id != "" ? var.leader_ami_id : data.aws_ami.al2023.id
  worker_ami_id           = var.worker_ami_id != "" ? var.worker_ami_id : data.aws_ami.al2023.id
  ssh_skip_options        = " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
}

resource "aws_security_group" "loadtest" {
  name        = "${local.cluster_name}-loadtest-sg"
  description = "Allow inbound access for Locust load testing"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    description = "HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = local.web_cidr_ingress_blocks
  }

  ingress {
    description = "HTTPS"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = local.web_cidr_ingress_blocks
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_ingress_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      "Name" = "${local.cluster_name}-loadtest-sg"
    }
  )
}

resource "aws_iam_role" "loadtest" {
  name = "${local.cluster_name}-loadtest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "AllowEC2AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      "Name" = "${local.cluster_name}-loadtest-role"
    }
  )
}

resource "aws_iam_instance_profile" "loadtest" {
  name = "${local.cluster_name}-loadtest-profile"
  role = aws_iam_role.loadtest.name
}

resource "tls_private_key" "loadtest" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "loadtest" {
  key_name   = "${local.cluster_name}-loadtest-keypair"
  public_key = tls_private_key.loadtest.public_key_openssh
}

resource "null_resource" "key_pair_exporter" {
  depends_on = [aws_key_pair.loadtest]

  provisioner "local-exec" {
    command = local.export_private_key_cmd
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "aws_instance" "leader" {
  ami                         = local.leader_ami_id
  instance_type               = var.leader_instance_type
  associate_public_ip_address = var.leader_associate_public_ip
  monitoring                  = var.leader_monitoring
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.loadtest.id]
  iam_instance_profile        = aws_iam_instance_profile.loadtest.name
  user_data_base64            = local.node_user_data

  key_name = aws_key_pair.loadtest.key_name

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.loadtest.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "echo '${tls_private_key.loadtest.private_key_pem}' > ~/.ssh/id_rsa",
      "chmod 600 ~/.ssh/id_rsa",
      "sudo mkdir -p ${local.loadtest_dir_destination} || true",
      "sudo chown ${var.ssh_user}:${var.ssh_user} ${local.loadtest_dir_destination} || true"
    ]
  }

  provisioner "file" {
    destination = local.loadtest_dir_destination
    source      = var.loadtest_dir_source
  }

  tags = merge(
    var.tags,
    var.leader_tags,
    {
      "Name"  = "${local.cluster_name}-leader",
      "nodes" = join(",", aws_instance.nodes[*].private_ip)
    }
  )
}

resource "aws_instance" "nodes" {
  count = var.node_size

  ami                         = local.worker_ami_id
  instance_type               = var.worker_instance_type
  associate_public_ip_address = var.worker_associate_public_ip
  monitoring                  = var.worker_monitoring
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.loadtest.id]
  iam_instance_profile        = aws_iam_instance_profile.loadtest.name
  user_data_base64            = local.node_user_data

  key_name = aws_key_pair.loadtest.key_name

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.loadtest.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "echo '${tls_private_key.loadtest.private_key_pem}' > ~/.ssh/id_rsa",
      "chmod 600 ~/.ssh/id_rsa",
      "sudo mkdir -p ${local.loadtest_dir_destination} || true",
      "sudo chown ${var.ssh_user}:${var.ssh_user} ${local.loadtest_dir_destination} || true"
    ]
  }

  provisioner "file" {
    destination = local.loadtest_dir_destination
    source      = var.loadtest_dir_source
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'START EXECUTION'",
      local.wait_for_setup_cmd,
      "sleep 10"
    ]
  }

  tags = merge(
    var.tags,
    var.worker_tags,
    {
      "Name" = "${local.cluster_name}-worker"
    }
  )
}

locals {
  leader_private_ip        = aws_instance.leader.private_ip
  node_entrypoint_rendered = replace(local.node_entrypoint, "{LEADER_IP}", local.leader_private_ip)
  nodes_count_non_zero     = var.node_size > 0 ? var.node_size : 1
  split_enabled            = var.split_data_mass_between_nodes.enable && var.node_size > 0
  split_filenames          = local.split_enabled ? var.split_data_mass_between_nodes.data_mass_filenames : []
  split_cmd_template       = "split -a 3 -d -nr/${local.nodes_count_non_zero} ${local.loadtest_dir_destination}/{FILENAME} ${local.loadtest_dir_destination}/{FILENAME}"
}

locals {
  leader_split_commands = [
    for file in local.split_filenames : replace(local.split_cmd_template, "{FILENAME}", file)
  ]

  leader_cleanup_commands = flatten([
    for file in local.split_filenames : [
      for host in aws_instance.nodes : replace(
        replace(
          "ssh${local.ssh_skip_options}${var.ssh_user}@{HOST} -c \"rm -rf ${local.loadtest_dir_destination}/{FILE}\" || true",
          "{FILE}",
          file
        ),
        "{HOST}",
        host.private_ip
      )
    ]
  ])

  leader_scp_commands = flatten([
    for file in local.split_filenames : [
      for index, host in aws_instance.nodes : replace(
        replace(
          replace(
            "scp${local.ssh_skip_options}${local.loadtest_dir_destination}/{FILE_IN} ${var.ssh_user}@{HOST}:${local.loadtest_dir_destination}/{FILE_OUT}",
            "{FILE_IN}",
            "${file}${format("%03d", index)}"
          ),
          "{FILE_OUT}",
          file
        ),
        "{HOST}",
        host.private_ip
      )
    ]
  ])

  leader_split_workflow = length(local.split_filenames) > 0 ? concat(
    ["echo AUTO SPLITTER ENABLED"],
    local.leader_split_commands,
    local.leader_cleanup_commands,
    local.leader_scp_commands
  ) : ["echo AUTO SPLITTER DISABLED"]
}

resource "null_resource" "spliter_execute_command" {
  connection {
    host        = coalesce(aws_instance.leader.public_ip, aws_instance.leader.private_ip)
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.loadtest.private_key_pem
  }

  provisioner "remote-exec" {
    inline = local.leader_split_workflow
  }
}

resource "null_resource" "setup_leader" {
  depends_on = [
    aws_instance.leader,
    aws_instance.nodes
  ]

  connection {
    host        = coalesce(aws_instance.leader.public_ip, aws_instance.leader.private_ip)
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.loadtest.private_key_pem
  }

  provisioner "remote-exec" {
    inline = ["echo 'SETUP LEADER'"]
  }
}

resource "null_resource" "setup_nodes" {
  count = var.auto_start_locust ? var.node_size : 0

  depends_on = [
    aws_instance.leader,
    aws_instance.nodes
  ]

  connection {
    host        = coalesce(aws_instance.nodes[count.index].public_ip, aws_instance.nodes[count.index].private_ip)
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.loadtest.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "echo SETUP NODE ${count.index}",
      "cd ${local.loadtest_dir_destination}",
      local.node_entrypoint_rendered,
      "sleep 1"
    ]
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "executor" {
  count = var.auto_start_locust ? 1 : 0

  depends_on = [
    aws_instance.leader,
    aws_instance.nodes,
    null_resource.setup_nodes,
    null_resource.setup_leader,
    null_resource.spliter_execute_command
  ]

  connection {
    host        = coalesce(aws_instance.leader.public_ip, aws_instance.leader.private_ip)
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.loadtest.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'START EXECUTION'",
      local.wait_for_setup_cmd
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 777 /var/www/html -Rf || true",
      "sudo rm -rf /var/www/html/* || true",
      "sudo rm -rf ${local.loadtest_dir_destination}/logs || true"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "echo DIR: ${local.loadtest_dir_destination}",
      "cd ${local.loadtest_dir_destination}",
      local.leader_entrypoint,
      "sleep 1"
    ]
  }

  triggers = {
    always_run = timestamp()
  }
}
