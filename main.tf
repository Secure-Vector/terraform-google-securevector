###############################################################################
# SecureVector engine on Google Cloud Run
#
# One `terraform apply` stands up the SecureVector threat-monitor engine in YOUR
# Google Cloud project: a Cloud Run service (managed HTTPS, scale-to-zero) with
# an optional GCS-backed persistence volume for the tamper-evident audit chain.
###############################################################################

locals {
  # Cloud-specific: the deployed engine's HTTPS URL. The shared runtime.tf
  # consumes this local — every cloud module must define local.base_url.
  base_url = google_cloud_run_v2_service.default.uri

  bucket_name = var.persistence_bucket_name != "" ? var.persistence_bucket_name : "${var.project_id}-${var.name}-data"

  # Engine container env. Only env vars the app actually reads
  # (verified against securevector-ai-threat-monitor). Host/port are NOT env —
  # they are CLI args on the launch command (see var.container_command). Empty
  # optional values are filtered out so they are never set to "".
  #
  #   SECUREVECTOR_API_KEY    — engine's OUTBOUND cloud key (personal cloud mode;
  #                             cloud_sync sends it as X-Api-Key). NOT an inbound
  #                             auth gate — it does not protect /analyze.
  #   SECUREVECTOR_API_URL    — override the SecureVector cloud API base URL.
  #   SECUREVECTOR_ENROLL_TOKEN — svet_* org enrollment token. Consumed by the
  #                             `securevector-app enroll` subcommand, so the IMAGE
  #                             ENTRYPOINT must enroll before serving (see README).
  container_env = merge(
    var.securevector_api_key != "" ? { SECUREVECTOR_API_KEY = var.securevector_api_key } : {},
    var.securevector_api_url != "" ? { SECUREVECTOR_API_URL = var.securevector_api_url } : {},
    var.cloud_connect_token != "" ? { SECUREVECTOR_ENROLL_TOKEN = var.cloud_connect_token } : {},
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

      # Launch command. The app binds host/port from CLI args (--host/--port),
      # NOT env. Empty list (default) = defer to the image's own ENTRYPOINT,
      # which per the #182 image contract must bind 0.0.0.0:container_port and
      # enroll from SECUREVECTOR_ENROLL_TOKEN (when set) before serving. Set a
      # non-empty list to override, e.g.
      # ["securevector-app","--web","--host","0.0.0.0","--port","8741"].
      command = length(var.container_command) > 0 ? var.container_command : null

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

      # Persistence mounts at the engine's data dir. The app has NO data-dir env
      # override — it uses $HOME/.local/share/securevector/threat-monitor — so
      # persistence_mount_path MUST equal that path in the published image (the
      # image must run as a user whose HOME maps here). See README / #182.
      dynamic "volume_mounts" {
        for_each = var.enable_persistence ? [1] : []
        content {
          name       = "data"
          mount_path = var.persistence_mount_path
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
# Public access (gated at the app layer by securevector_api_key)
###############################################################################

resource "google_cloud_run_v2_service_iam_member" "public" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_service.default.location
  name     = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
