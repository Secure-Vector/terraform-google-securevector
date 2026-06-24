###############################################################################
# EU-region example — SecureVector engine on Cloud Run, deployed in the EU
#
# Same shape as ../free-tier, but pinned to an EU region for data residency.
# Both the Cloud Run service and its GCS persistence bucket are created in
# `region`, so setting an EU region keeps all governance/runtime data inside the
# EU. Nothing in this module replicates data to another region.
#
# Data residency: the engine processes and stores agent/governance data only in
# the GCP project and region you deploy into. SecureVector never receives it.
# See the module README for the residency posture.
#
# Default region here is europe-west1 (Belgium); europe-west4 (Netherlands) and
# other EU regions also work — just change the `region` value below.
#
# Usage:
#   terraform init
#   terraform apply -var="project_id=YOUR_PROJECT" -var="securevector_api_key=$(openssl rand -hex 24)"
#   terraform output -raw runtime_snippet
#   terraform destroy   # clean teardown, no leftover billing
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 7.0"
    }
  }
}

variable "project_id" {
  type = string
}

variable "securevector_api_key" {
  type      = string
  sensitive = true
}

provider "google" {
  project = var.project_id
}

module "securevector" {
  source = "../../"

  project_id           = var.project_id
  region               = "europe-west1" # EU (Belgium); governs data residency
  securevector_runtime = "langchain"

  # Cheapest trial posture
  min_instances        = 0
  securevector_api_key = var.securevector_api_key
  bucket_force_destroy = true
}

output "dashboard_url" {
  value = module.securevector.dashboard_url
}

output "runtime_snippet" {
  value = module.securevector.runtime_snippet
}
