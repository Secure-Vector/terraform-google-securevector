###############################################################################
# SecureVector engine on Google Cloud Run
#
# One `terraform apply` stands up the SecureVector threat-monitor engine in YOUR
# Google Cloud project: a Cloud Run service (managed HTTPS, scale-to-zero) with
# an optional GCS-backed persistence volume for the tamper-evident audit chain.
###############################################################################

locals {
  bucket_name = var.persistence_bucket_name != "" ? var.persistence_bucket_name : "${var.project_id}-${var.name}-data"

  # Server-mode contract passed to the engine container. These env names track
  # the documented "server mode" in securevector-ai-threat-monitor (bind beyond
  # loopback, app-layer auth, persistence path). Empty optional values are
  # filtered out so they are never set to "".
  container_env = merge(
    {
      SECUREVECTOR_HOST = "0.0.0.0"
      SECUREVECTOR_PORT = tostring(var.container_port)
    },
    var.auth_token != "" ? { SECUREVECTOR_AUTH_TOKEN = var.auth_token } : {},
    var.cloud_connect_token != "" ? { SECUREVECTOR_CLOUD_CONNECT_TOKEN = var.cloud_connect_token } : {},
    var.enable_persistence ? { SECUREVECTOR_DATA_DIR = "/data" } : {},
    var.extra_env,
  )

  required_apis = toset(concat(
    ["run.googleapis.com"],
    var.enable_persistence ? ["storage.googleapis.com"] : [],
  ))
}

###############################################################################
# Required APIs
###############################################################################

resource "google_project_service" "required" {
  for_each = var.enable_apis ? local.required_apis : toset([])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

###############################################################################
# Persistence — GCS-backed volume for the audit hash-chain
###############################################################################

resource "google_storage_bucket" "data" {
  count = var.enable_persistence ? 1 : 0

  project                     = var.project_id
  name                        = local.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.bucket_force_destroy
  labels                      = var.labels

  depends_on = [google_project_service.required]
}

###############################################################################
# Cloud Run service — the engine
###############################################################################

resource "google_cloud_run_v2_service" "default" {
  project  = var.project_id
  name     = var.name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"
  labels   = var.labels

  # Allow `terraform destroy` to remove the service cleanly (low-commitment trial).
  deletion_protection = false

  template {
    service_account = var.service_account_email != "" ? var.service_account_email : null

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = local.container_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "volume_mounts" {
        for_each = var.enable_persistence ? [1] : []
        content {
          name       = "data"
          mount_path = "/data"
        }
      }
    }

    dynamic "volumes" {
      for_each = var.enable_persistence ? [1] : []
      content {
        name = "data"
        gcs {
          bucket    = google_storage_bucket.data[0].name
          read_only = false
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}

###############################################################################
# Public access (gated at the app layer by auth_token)
###############################################################################

resource "google_cloud_run_v2_service_iam_member" "public" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_service.default.location
  name     = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
