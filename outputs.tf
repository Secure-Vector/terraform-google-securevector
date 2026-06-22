# Cloud-specific outputs. The runtime/client snippet (output "runtime_snippet")
# lives in the shared runtime.tf. local.base_url is defined in main.tf.

output "dashboard_url" {
  description = "The HTTPS URL of the SecureVector engine dashboard (Cloud Run managed TLS)."
  value       = local.base_url
}

output "health_url" {
  description = "Load-balancer / uptime health endpoint."
  value       = "${local.base_url}/health"
}

output "service_name" {
  description = "Name of the deployed Cloud Run service."
  value       = google_cloud_run_v2_service.default.name
}

output "region" {
  description = "Region the service was deployed to."
  value       = var.region
}

output "persistence_bucket" {
  description = "GCS bucket backing the audit hash-chain volume (null when persistence is disabled)."
  value       = var.enable_persistence ? google_storage_bucket.data[0].name : null
}
