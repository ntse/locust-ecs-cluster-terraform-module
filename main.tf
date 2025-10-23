data "aws_region" "current" {}

data "aws_subnet" "private_primary" {
  id = element(var.private_subnet_ids, 0)
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value
}

locals {
  cluster_name = var.cluster_name

  raw_cluster_slug       = lower(trim(join("-", regexall("[0-9A-Za-z-]+", var.cluster_name)), "-"))
  sanitized_cluster_name = local.raw_cluster_slug != "" ? local.raw_cluster_slug : "locust"
  web_ingress_cidrs      = var.web_cidr_ingress_blocks

  efs_access_path = startswith(var.loadtest_dir_destination, "/") ? var.loadtest_dir_destination : "/${var.loadtest_dir_destination}"

  ecs_shared_mount_path = local.efs_access_path
  ecs_locustfile_path   = "${local.ecs_shared_mount_path}/${var.locust_plan_filename}"

  load_balancer_cidr_blocks = [for subnet in values(data.aws_subnet.public) : subnet.cidr_block]

  locust_object_source       = "${trimsuffix(var.loadtest_dir_source, "/")}/${var.locust_plan_filename}"
  requirements_object_source = "${trimsuffix(var.loadtest_dir_source, "/")}/${var.requirements_filename}"

  s3_bucket_name     = "${local.sanitized_cluster_name}-${random_id.storage.hex}-locust-assets"
  datasync_task_name = "${var.cluster_name}-locust-assets-sync"
  log_group_name     = "/aws/ecs/${local.cluster_name}"
}

resource "random_id" "storage" {
  byte_length = 4
}

############################################################
# Security groups
############################################################

resource "aws_security_group" "master" {
  name        = "${local.cluster_name}-master-sg"
  description = "Security group for Locust master task"
  vpc_id      = var.vpc_id

  ingress {
    description = "Load balancer UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = local.load_balancer_cidr_blocks
  }

  ingress {
    description = "Load balancer command"
    from_port   = 5557
    to_port     = 5557
    protocol    = "tcp"
    cidr_blocks = local.load_balancer_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-master-sg" })
}

resource "aws_security_group" "workers" {
  name        = "${local.cluster_name}-workers-sg"
  description = "Security group for Locust worker tasks"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-workers-sg" })
}

resource "aws_security_group_rule" "workers_to_lb" {
  type              = "egress"
  security_group_id = aws_security_group.workers.id
  from_port         = 5557
  to_port           = 5557
  protocol          = "tcp"
  cidr_blocks       = local.load_balancer_cidr_blocks
}

resource "aws_security_group" "datasync" {
  name        = "${local.cluster_name}-datasync-sg"
  description = "Security group for AWS DataSync ENIs"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-datasync-sg" })
}

resource "aws_security_group" "efs" {
  name        = "${local.cluster_name}-efs-sg"
  description = "Allow NFS access to the shared Locust EFS file system"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-efs-sg" })
}

resource "aws_security_group_rule" "efs_from_master" {
  type                     = "ingress"
  security_group_id        = aws_security_group.efs.id
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "efs_from_workers" {
  type                     = "ingress"
  security_group_id        = aws_security_group.efs.id
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.workers.id
}

resource "aws_security_group_rule" "efs_from_datasync" {
  type                     = "ingress"
  security_group_id        = aws_security_group.efs.id
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.datasync.id
}

############################################################
# Shared storage
############################################################

resource "aws_efs_file_system" "shared" {
  creation_token   = "${local.cluster_name}-locust-efs"
  encrypted        = true
  performance_mode = "generalPurpose"

  tags = merge(var.tags, { Name = "${local.cluster_name}-locust-efs" })
}

resource "aws_efs_mount_target" "shared" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = element(var.private_subnet_ids, count.index)
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "shared" {
  file_system_id = aws_efs_file_system.shared.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = local.efs_access_path

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0770"
    }
  }
}

resource "aws_s3_bucket" "shared" {
  bucket        = local.s3_bucket_name
  force_destroy = true

  tags = merge(var.tags, { Name = "${local.cluster_name}-locust-assets" })
}

resource "aws_s3_bucket_versioning" "shared" {
  bucket = aws_s3_bucket.shared.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "shared" {
  bucket = aws_s3_bucket.shared.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "locust_plan" {
  bucket       = aws_s3_bucket.shared.id
  key          = var.locust_plan_filename
  source       = local.locust_object_source
  etag         = filemd5(local.locust_object_source)
  content_type = "text/x-python"
}

resource "aws_s3_object" "requirements" {
  bucket = aws_s3_bucket.shared.id
  key    = var.requirements_filename
  source = local.requirements_object_source
  etag   = filemd5(local.requirements_object_source)
}

resource "aws_cloudwatch_log_group" "locust" {
  name              = local.log_group_name
  retention_in_days = 30

  tags = merge(var.tags, { Name = "${local.cluster_name}-ecs-logs" })
}

############################################################
# DataSync to sync assets into EFS
############################################################

data "aws_iam_policy_document" "datasync" {
  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListBucketVersions",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = [aws_s3_bucket.shared.arn, "${aws_s3_bucket.shared.arn}/*"]
  }

  statement {
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets"
    ]
    resources = [aws_efs_file_system.shared.arn, aws_efs_access_point.shared.arn]
  }

  statement {
    actions = [
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "datasync" {
  name = "${local.cluster_name}-datasync-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "datasync.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${local.cluster_name}-datasync-role" })
}

resource "aws_iam_role_policy" "datasync" {
  name   = "${local.cluster_name}-datasync-policy"
  role   = aws_iam_role.datasync.id
  policy = data.aws_iam_policy_document.datasync.json
}

resource "aws_datasync_location_s3" "shared" {
  s3_bucket_arn = aws_s3_bucket.shared.arn
  subdirectory  = "/"

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync.arn
  }
}

resource "aws_datasync_location_efs" "shared" {
  efs_file_system_arn         = aws_efs_file_system.shared.arn
  access_point_arn            = aws_efs_access_point.shared.arn
  file_system_access_role_arn = aws_iam_role.datasync.arn
  in_transit_encryption       = "TLS1_2"

  ec2_config {
    security_group_arns = [aws_security_group.datasync.arn]
    subnet_arn          = data.aws_subnet.private_primary.arn
  }
}

resource "aws_datasync_task" "s3_to_efs" {
  name                     = local.datasync_task_name
  source_location_arn      = aws_datasync_location_s3.shared.arn
  destination_location_arn = aws_datasync_location_efs.shared.arn

  options {
    transfer_mode = "CHANGED"
    verify_mode   = "POINT_IN_TIME_CONSISTENT"
  }

  tags = var.tags
}

resource "null_resource" "datasync_trigger" {
  depends_on = [aws_datasync_task.s3_to_efs]

  triggers = {
    locust_plan_hash  = filemd5(local.locust_object_source)
    requirements_hash = filemd5(local.requirements_object_source)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      AWS_DEFAULT_REGION=${data.aws_region.current.id} aws datasync start-task-execution --task-arn ${aws_datasync_task.s3_to_efs.arn} >/dev/null
    EOT
  }
}

############################################################
# Networking - NLB
############################################################

resource "aws_lb" "master" {
  name                             = substr("${local.cluster_name}-nlb", 0, 32)
  load_balancer_type               = "network"
  enable_cross_zone_load_balancing = true
  subnets                          = var.public_subnet_ids

  tags = merge(var.tags, { Name = "${local.cluster_name}-nlb" })
}

resource "aws_lb_target_group" "master_ui" {
  name        = substr("${local.cluster_name}-ui", 0, 32)
  port        = 8080
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled  = true
    protocol = "TCP"
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-ui" })
}

resource "aws_lb_target_group" "master_command" {
  name        = substr("${local.cluster_name}-cmd", 0, 32)
  port        = 5557
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled  = true
    protocol = "TCP"
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-cmd" })
}

resource "aws_lb_listener" "master_ui" {
  load_balancer_arn = aws_lb.master.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.master_ui.arn
  }
}

resource "aws_lb_listener" "master_command" {
  load_balancer_arn = aws_lb.master.arn
  port              = 5557
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.master_command.arn
  }
}

############################################################
# ECS cluster and roles
############################################################

resource "aws_iam_role" "ecs_task" {
  name = "${local.cluster_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${local.cluster_name}-ecs-task-role" })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_efs" {
  name = "${local.cluster_name}-ecs-efs"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = [
          aws_efs_file_system.shared.arn,
          aws_efs_access_point.shared.arn
        ]
      }
    ]
  })
}

resource "aws_ecs_cluster" "locust" {
  name = "${local.cluster_name}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "locust" {
  cluster_name = aws_ecs_cluster.locust.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 1
    capacity_provider = "FARGATE"
  }
}

############################################################
# Task definitions
############################################################

resource "aws_ecs_task_definition" "master" {
  family                   = "${local.cluster_name}-master"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name       = "locust-master"
      image      = "locustio/locust:${var.locust_version}"
      essential  = true
      entryPoint = ["sh", "-c"]
      command = [
        format(
          "if [ -f %s/requirements.txt ]; then pip install --no-cache-dir -r %s/requirements.txt; fi && exec locust --master --web-host=0.0.0.0 --web-port=8080 --expect-workers=%d -f %s",
          local.efs_access_path,
          local.efs_access_path,
          max(var.worker_count, 1),
          local.ecs_locustfile_path
        )
      ]
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        },
        {
          containerPort = 5557
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          containerPath = local.efs_access_path
          sourceVolume  = "shared"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "master"
        }
      }
    }
  ])

  volume {
    name = "shared"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.shared.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.shared.id
        iam             = "ENABLED"
      }
    }
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.cluster_name}-worker"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name       = "locust-worker"
      image      = "locustio/locust:${var.locust_version}"
      essential  = true
      entryPoint = ["sh", "-c"]
      command = [
        format(
          "if [ -f %s/requirements.txt ]; then pip install --no-cache-dir -r %s/requirements.txt; fi && exec locust --worker --master-host=%s --master-port=5557 -f %s",
          local.efs_access_path,
          local.efs_access_path,
          aws_lb.master.dns_name,
          local.ecs_locustfile_path
        )
      ]
      environment = [
        {
          name  = "LOCUST_WORKER"
          value = "1"
        }
      ]
      mountPoints = [
        {
          containerPath = local.efs_access_path
          sourceVolume  = "shared"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])

  volume {
    name = "shared"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.shared.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.shared.id
        iam             = "ENABLED"
      }
    }
  }
}

############################################################
# ECS services
############################################################

resource "aws_ecs_service" "master" {
  name                               = "${local.cluster_name}-master"
  cluster                            = aws_ecs_cluster.locust.id
  task_definition                    = aws_ecs_task_definition.master.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  load_balancer {
    target_group_arn = aws_lb_target_group.master_ui.arn
    container_name   = "locust-master"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.master_command.arn
    container_name   = "locust-master"
    container_port   = 5557
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.master.id]
    assign_public_ip = false
  }

  depends_on = [
    null_resource.datasync_trigger,
    aws_lb_listener.master_ui,
    aws_lb_listener.master_command
  ]

  tags = merge(var.tags, { Name = "${local.cluster_name}-master" })
}

resource "aws_ecs_service" "workers" {
  name            = "${local.cluster_name}-workers"
  cluster         = aws_ecs_cluster.locust.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.workers.id]
    assign_public_ip = false
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-workers" })
}

############################################################
# CloudWatch log group created earlier (aws_cloudwatch_log_group.locust)
############################################################
