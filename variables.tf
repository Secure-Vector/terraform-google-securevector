###############################################################################
# Required
###############################################################################

variable "project_id" {
  description = "The Google Cloud project ID to deploy the SecureVector engine into. The container, bucket, and IAM all live in *your* project — data stays in your tenant."
  type        = string
}

###############################################################################
# Placement & naming
###############################################################################

variable "region" {
  description = "Cloud Run region (e.g. us-central1, europe-west1). Pick the region closest to your agents / data-residency requirement."
  type        = string
  default     = "us-central1"
}

variable "name" {
  description = "Base name for the Cloud Run service and derived resources. Must be lowercase, RFC1035-safe."
  type        = string
  default     = "securevector"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name)) && length(var.name) <= 49
    error_message = "name must be lowercase, start with a letter, contain only letters/digits/hyphens, and be <= 49 chars."
  }
}

variable "labels" {
  description = "Labels applied to created resources (Cloud Run service, bucket)."
  type        = map(string)
  default     = {}
}

###############################################################################
# Container image
###############################################################################

variable "image" {
  description = "Container image for the SecureVector engine. Defaults to the public ghcr.io image published from securevector-ai-threat-monitor. Pin to a version tag for production."
  type        = string
  default     = "ghcr.io/secure-vector/securevector-ai-threat-monitor:latest"
}

variable "container_port" {
  description = "Port the engine listens on inside the container. Cloud Run routes HTTPS traffic to this port. The image/command must bind this port on 0.0.0.0."
  type        = number
  default     = 8741

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_command" {
  description = "Override the container entrypoint. Empty (default) defers to the image ENTRYPOINT. The app takes host/port as CLI args (NOT env), so a working override looks like [\"securevector-app\", \"--web\", \"--host\", \"0.0.0.0\", \"--port\", \"8741\"]. (Enrollment from SECUREVECTOR_ENROLL_TOKEN must be handled by the image entrypoint, not this command.)"
  type        = list(string)
  default     = []
}

###############################################################################
# Scaling & resources (free-tier-friendly defaults: scale-to-zero)
###############################################################################

variable "cpu" {
  description = "CPU limit per instance (Cloud Run format, e.g. \"1\", \"2\")."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance (Cloud Run format, e.g. \"512Mi\", \"1Gi\")."
  type        = string
  default     = "512Mi"
}

variable "min_instances" {
  description = "Minimum number of instances. 0 = scale-to-zero (cheapest; cold start on first request). Set to 1 to keep the dashboard warm."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instances >= 0
    error_message = "min_instances must be >= 0."
  }
}

variable "max_instances" {
  description = "Maximum number of instances."
  type        = number
  default     = 2

  validation {
    condition     = var.max_instances >= 1
    error_message = "max_instances must be >= 1."
  }
}

variable "service_account_email" {
  description = "Optional runtime service account for the Cloud Run service. Empty = the project's default compute service account."
  type        = string
  default     = ""
}

variable "execution_environment" {
  description = "Cloud Run execution environment override: \"\" (default) auto-selects GEN2 when persistence is on (required for GCS volume mounts) and the provider default otherwise; or pin EXECUTION_ENVIRONMENT_GEN1 / EXECUTION_ENVIRONMENT_GEN2."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "EXECUTION_ENVIRONMENT_GEN1", "EXECUTION_ENVIRONMENT_GEN2"], var.execution_environment)
    error_message = "execution_environment must be \"\", EXECUTION_ENVIRONMENT_GEN1, or EXECUTION_ENVIRONMENT_GEN2."
  }
}

variable "deletion_protection" {
  description = "Cloud Run deletion protection. Default false so `terraform destroy` works for trials; set true to protect a production service."
  type        = bool
  default     = false
}

###############################################################################
# Access & auth
#
# Two independent layers:
#   - ingress_token  -> SECUREVECTOR_INGRESS_TOKEN: APP-LAYER inbound gate. When
#     set, the engine requires the credential on every request (Authorization:
#     Bearer or X-Api-Key); /health stays open. Validated by the ingress_auth
#     middleware in securevector-ai-threat-monitor (pending release).
#   - allow_unauthenticated -> Cloud Run IAM: NETWORK-LAYER gate.
# Use either or both. securevector_api_key below is the engine's OUTBOUND cloud
# key, NOT an inbound gate — don't confuse the two.
###############################################################################

variable "allow_unauthenticated" {
  description = "Grant roles/run.invoker to allUsers so the run.app URL is reachable over the public internet. Pair with ingress_token for app-layer auth, or set FALSE to require Google IAM (gcloud run services proxy / IAP) as the gate."
  type        = bool
  default     = true
}

variable "ingress_token" {
  description = "App-layer inbound credential. When set, the engine requires it on every request (sent as Authorization: Bearer <token> or X-Api-Key: <token>); /health stays open for probes. Header-capable clients (OpenClaw, curl) can pass it today; SDK/JS-hook client-side forwarding is still rolling out (#182). Empty = no app-layer gate (rely on Cloud Run IAM)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "securevector_api_key" {
  description = "OUTBOUND cloud credential: a personal API key (svpk_* / legacy) the engine presents to the SecureVector cloud (sent as X-Api-Key by cloud_sync) for personal cloud mode / enhanced detection. This is NOT an inbound gate and does not protect /analyze. Empty = no cloud key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "securevector_api_url" {
  description = "Optional override for the SecureVector cloud API base URL (SECUREVECTOR_API_URL). Empty = the app's built-in default."
  type        = string
  default     = ""
}

###############################################################################
# Cloud Connect bridge (optional) — turns this self-hosted node into a member
# of the SecureVector managed fleet (the OSS-self-host -> paid Pro/Enterprise
# on-ramp). Leave empty to stay fully self-hosted.
###############################################################################

variable "cloud_connect_token" {
  description = "Optional svet_* org ENROLLMENT token (passed as SECUREVECTOR_ENROLL_TOKEN). Enrolls the node into the org FLEET view AND receives signed policy bundles (Policy Sync ON). NOTE: only the svet_* enroll path enables policy sync; a personal key (svpk_*) goes in securevector_api_key instead. Requires the image entrypoint to run `securevector-app enroll` before serving (see README / #182). Empty = pure self-host, no enrollment."
  type        = string
  default     = ""
  sensitive   = true
}

# NOTE: variable "securevector_runtime" lives in the shared runtime.tf (kept
# identical across all terraform-<cloud>-securevector repos).

###############################################################################
# Persistence — durable audit hash-chain. v1 = SQLite on a GCS-backed volume.
###############################################################################

variable "enable_persistence" {
  description = "Mount a GCS-backed volume at persistence_mount_path so the audit hash-chain survives instance restarts (forces the GEN2 execution environment). Disable for a stateless throwaway trial."
  type        = bool
  default     = true
}

variable "persistence_bucket_name" {
  description = "Name of the GCS bucket for persistence. Empty = derive \"<project_id>-<name>-data\". Bucket names are globally unique."
  type        = string
  default     = ""
}

variable "persistence_mount_path" {
  description = "Path the persistence volume mounts at inside the container. The app has NO data-dir env override — it stores its SQLite DB / audit chain at $HOME/.local/share/securevector/threat-monitor — so this MUST match that path in the published image. Default assumes HOME=/home/securevector."
  type        = string
  default     = "/home/securevector/.local/share/securevector/threat-monitor"
}

variable "bucket_force_destroy" {
  description = "Allow `terraform destroy` to delete the persistence bucket even if it contains objects. Set true for low-commitment trials (clean teardown); keep false to protect audit data."
  type        = bool
  default     = false
}

###############################################################################
# API enablement & escape hatches
###############################################################################

variable "enable_apis" {
  description = "Enable the required Google APIs (run.googleapis.com, and storage.googleapis.com when persistence is on) on the project. Set false if your org manages API enablement separately."
  type        = bool
  default     = true
}

variable "extra_env" {
  description = "Additional environment variables to pass to the engine container (advanced / forward-compat with future server-mode flags)."
  type        = map(string)
  default     = {}
}
