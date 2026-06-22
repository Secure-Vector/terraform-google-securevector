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
  description = "Port the engine listens on inside the container. Cloud Run routes HTTPS traffic to this port."
  type        = number
  default     = 8741
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
# The SecureVector engine is single-user by origin. v1 fronts it with an
# application-layer bearer token (auth_token). When allow_unauthenticated is
# true, Cloud Run serves the run.app URL publicly over managed HTTPS and the
# bearer token is what actually gates access — so SET auth_token in any
# internet-reachable deployment.
###############################################################################

variable "allow_unauthenticated" {
  description = "Grant roles/run.invoker to allUsers so the run.app URL is reachable over the public internet (gated by auth_token at the app layer). Set false to require Google IAM (gcloud proxy / IAP) instead."
  type        = bool
  default     = true
}

variable "auth_token" {
  description = "Bearer token the engine requires on inbound requests (application-layer gate). STRONGLY recommended when allow_unauthenticated = true. Clients pass it via the SDK/plugin. Empty = no app-layer gate (rely on Cloud Run IAM only)."
  type        = string
  default     = ""
  sensitive   = true
}

###############################################################################
# Cloud Connect bridge (optional) — turns this self-hosted node into a member
# of the SecureVector managed fleet (the OSS-self-host -> paid Pro/Enterprise
# on-ramp). Leave empty to stay fully self-hosted.
###############################################################################

variable "cloud_connect_token" {
  description = "Optional SecureVector Cloud Connect enrollment token (svet_* / svpk_*). When set, the node enrolls into the managed fleet view. Empty = pure self-host, no outbound enrollment."
  type        = string
  default     = ""
  sensitive   = true
}

###############################################################################
# Runtime snippet — emits the wired SDK/plugin install snippet as an output.
###############################################################################

variable "securevector_runtime" {
  description = "Which client to emit a copy-paste wiring snippet for as a Terraform output. One of: none, langchain, langgraph, crewai, claude-code, cursor, codex."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "langchain", "langgraph", "crewai", "claude-code", "cursor", "codex"], var.securevector_runtime)
    error_message = "securevector_runtime must be one of: none, langchain, langgraph, crewai, claude-code, cursor, codex."
  }
}

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
