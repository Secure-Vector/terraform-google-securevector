###############################################################################
# Free-tier "try it" example
#
# Cheapest possible SecureVector engine on Cloud Run:
#   - scale-to-zero (you pay only when a request hits it)
#   - persistence on, but bucket force-destroys for a clean teardown
#   - public URL gated by a bearer token
#   - emits a wired LangChain snippet on apply
#
# Usage:
#   terraform init
#   terraform apply -var="project_id=YOUR_PROJECT" -var="auth_token=$(openssl rand -hex 24)"
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

variable "auth_token" {
  type      = string
  sensitive = true
}

provider "google" {
  project = var.project_id
}

module "securevector" {
  source = "../../"

  project_id           = var.project_id
  region               = "us-central1"
  securevector_runtime = "langchain"

  # Cheapest trial posture
  min_instances        = 0
  auth_token           = var.auth_token
  bucket_force_destroy = true
}

output "dashboard_url" {
  value = module.securevector.dashboard_url
}

output "runtime_snippet" {
  value = module.securevector.runtime_snippet
}
