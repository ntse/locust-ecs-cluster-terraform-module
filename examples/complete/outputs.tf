output "leader_public_ip" {
  description = "The public IP address of the leader server instance"
  value       = module.locust_cluster.leader_public_ip
}

output "leader_private_ip" {
  description = "The private IP address of the leader server instance"
  value       = module.locust_cluster.leader_private_ip
}

output "nodes_public_ip" {
  description = "The public IP addresses of the worker instances"
  value       = module.locust_cluster.nodes_public_ip
}

output "nodes_private_ip" {
  description = "The private IP addresses of the worker instances"
  value       = module.locust_cluster.nodes_private_ip
}

output "dashboard_url" {
  description = "Convenience URL for the Locust UI"
  value       = module.locust_cluster.dashboard_url
}