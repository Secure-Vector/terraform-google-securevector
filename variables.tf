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
}

variable "max_instances" {
  description = "Maximum number of instances."
  type        = number
  default     = 2
}

variable "service_account_email" {
  description = "Optional runtime service account for the Cloud Run service. Empty = the project's default compute service account."
  type        = string
  default     = ""
}

###############################################################################
# Access & auth
#
# IMPORTANT (verified against securevector-ai-threat-monitor): the engine has
# NO inbound auth gate today — SECUREVECTOR_API_KEY is the engine's OUTBOUND
# cloud key, not a per-caller credential. So the ONLY thing that protects a
# public deployment today is Cloud Run IAM (allow_unauthenticated = false).
# App-layer inbound auth is tracked in story #182.
###############################################################################

variable "allow_unauthenticated" {
  description = "Grant roles/run.invoker to allUsers so the run.app URL is reachable over the public internet. The engine has no inbound auth today, so set this to FALSE for any non-trial internet deployment and reach the service over Google IAM (gcloud run services proxy / IAP)."
  type        = bool
  default     = true
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
  description = "Mount a GCS-backed volume at /data so the audit hash-chain survives instance restarts. Disable for a stateless throwaway trial."
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
