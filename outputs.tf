output "leader_public_ip" {
  description = "The public IP address of the leader server instance"
  value       = aws_instance.leader.public_ip
}

output "leader_private_ip" {
  description = "The private IP address of the leader server instance"
  value       = aws_instance.leader.private_ip
}

output "nodes_public_ip" {
  description = "The public IP addresses of the worker instances"
  value       = aws_instance.nodes[*].public_ip
}

output "nodes_private_ip" {
  description = "The private IP addresses of the worker instances"
  value       = aws_instance.nodes[*].private_ip
}

output "dashboard_url" {
  description = "The URL of the Locust UI"
  value       = "http://${coalesce(aws_instance.leader.public_ip, aws_instance.leader.private_ip)}:8080"
}

output "security_group_id" {
  description = "ID of the security group securing the Locust cluster"
  value       = aws_security_group.loadtest.id
}

output "iam_role_name" {
  description = "Name of the IAM role attached to the Locust instances"
  value       = aws_iam_role.loadtest.name
}

output "key_pair_name" {
  description = "Name of the EC2 key pair generated for the cluster"
  value       = aws_key_pair.loadtest.key_name
}
