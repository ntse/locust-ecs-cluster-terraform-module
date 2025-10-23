output "dashboard_url" {
  description = "URL for the Locust UI."
  value       = module.locust_cluster.dashboard_url
}

output "locust_assets_bucket" {
  description = "S3 bucket where Locust assets should be uploaded."
  value       = module.locust_cluster.locust_assets_bucket
}

output "datasync_task_arn" {
  description = "AWS DataSync task used to synchronise S3 objects into EFS."
  value       = module.locust_cluster.datasync_task_arn
}
