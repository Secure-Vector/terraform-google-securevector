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
  # Credentials are NEVER inlined as plaintext env values (those are readable
  # in the revision spec and in Terraform state). Each sensitive value becomes
  # a Secret Manager secret referenced through env `value_source`
  # (secret_key_ref); Cloud Run resolves it at instance start. To keep a value
  # out of Terraform state entirely, pre-create the secret yourself and pass
  # its id via existing_secret_ids instead of the variable.
  #
  #   SECUREVECTOR_INGRESS_TOKEN — INBOUND gate (Authorization: Bearer or
  #                             X-Api-Key on every request; /health stays open).
  #   SECUREVECTOR_API_KEY    — OUTBOUND cloud key (personal cloud mode).
  #   SECUREVECTOR_ENROLL_TOKEN — svet_* org enrollment (entrypoint enrolls).
  secret_env_all = {
    SECUREVECTOR_INGRESS_TOKEN = var.ingress_token
    SECUREVECTOR_API_KEY       = var.securevector_api_key
    SECUREVECTOR_ENROLL_TOKEN  = var.cloud_connect_token
  }

  # for_each cannot iterate sensitive-derived collections, so the NAME set is
  # explicitly unwrapped (only the set-or-not bit leaks, never the value).
  secret_env_names = [
    for k, v in local.secret_env_all : k if nonsensitive(v != "")
  ]

  # Caller-supplied secret ids win over the corresponding variable.
  managed_secret_names = [
    for k in local.secret_env_names : k if !contains(keys(var.existing_secret_ids), k)
  ]

  # env name -> secret reference consumed by the env value_source blocks.
  container_secret_refs = merge(
    { for k in local.managed_secret_names : k => google_secret_manager_secret.secret_env[k].secret_id },
    var.existing_secret_ids,
  )

  # Non-sensitive engine env stays as plain env values.
  container_env = merge(
    var.securevector_api_url != "" ? { SECUREVECTOR_API_URL = var.securevector_api_url } : {},
    var.extra_env,
  )

  # Cloud Run resolves secret refs with the RUNTIME service account.
  runtime_sa_email = var.service_account_email != "" ? var.service_account_email : "${data.google_project.this.number}-compute@developer.gserviceaccount.com"

  required_apis = toset(concat(
    ["run.googleapis.com"],
    var.enable_persistence ? ["storage.googleapis.com"] : [],
    length(local.secret_env_names) + length(var.existing_secret_ids) > 0 ? ["secretmanager.googleapis.com"] : [],
  ))
}

data "google_project" "this" {
  project_id = var.project_id
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
# Secrets — sensitive engine env lives in Secret Manager, not plaintext env
###############################################################################

resource "google_secret_manager_secret" "secret_env" {
  for_each = toset(local.managed_secret_names)

  project   = var.project_id
  secret_id = "${var.name}-${each.key}"
  labels    = var.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "secret_env" {
  for_each = toset(local.managed_secret_names)

  secret      = google_secret_manager_secret.secret_env[each.key].id
  secret_data = local.secret_env_all[each.key]
}

# The runtime service account resolves secret refs at instance start. Access is
# granted per-secret (least privilege) for module-created secrets; for
# existing_secret_ids the caller grants roles/secretmanager.secretAccessor.
resource "google_secret_manager_secret_iam_member" "runtime_access" {
  for_each = toset(local.managed_secret_names)

  project   = var.project_id
  secret_id = google_secret_manager_secret.secret_env[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runtime_sa_email}"
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

  # Default false so `terraform destroy` works for low-commitment trials; set
  # var.deletion_protection = true to protect a production service.
  deletion_protection = var.deletion_protection

  template {
    # GCS (gcsfuse) volume mounts are only supported on the 2nd-gen execution
    # environment, so force it when persistence is on (else use the provider
    # default / explicit override for faster, cheaper cold starts).
    execution_environment = var.execution_environment != "" ? var.execution_environment : (var.enable_persistence ? "EXECUTION_ENVIRONMENT_GEN2" : null)

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

      # Wait for the engine to finish booting (rules + Guardian load) before
      # Cloud Run routes traffic. /health is exempt from the ingress-auth gate,
      # so the probe works even when ingress_token is set.
      startup_probe {
        http_get {
          path = "/health"
          port = var.container_port
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 18
      }

      dynamic "env" {
        for_each = local.container_env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Sensitive env resolves from Secret Manager at instance start — the
      # value never appears in the revision spec.
      dynamic "env" {
        for_each = local.container_secret_refs
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
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

  depends_on = [
    google_project_service.required,
    google_secret_manager_secret_version.secret_env,
    google_secret_manager_secret_iam_member.runtime_access,
  ]
}

###############################################################################
# Public access (network layer). App-layer gating is via ingress_token; this
# only controls whether the run.app URL is reachable without Google IAM.
###############################################################################

resource "google_cloud_run_v2_service_iam_member" "public" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_service.default.location
  name     = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
