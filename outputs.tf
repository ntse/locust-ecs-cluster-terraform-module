output "dashboard_url" {
  description = "Public URL for the Locust web UI."
  value       = "http://${aws_lb.master.dns_name}:8080"
}

output "locust_assets_bucket" {
  description = "S3 bucket that stores the Locust assets replicated to EFS."
  value       = aws_s3_bucket.shared.bucket
}

output "datasync_task_arn" {
  description = "AWS DataSync task ARN that synchronises S3 objects to the shared EFS volume."
  value       = aws_datasync_task.s3_to_efs.arn
}

output "efs_file_system_id" {
  description = "ID of the shared EFS file system mounted by the Locust tasks."
  value       = aws_efs_file_system.shared.id
}
