locals {
  base_url = google_cloud_run_v2_service.default.uri

  # Copy-paste wiring snippet for the chosen client, pre-pointed at this engine.
  runtime_snippets = {
    none = <<-EOT
      Your SecureVector engine is live at:
        ${local.base_url}

      Point any SecureVector SDK or plugin at it:
        export SECUREVECTOR_BASE_URL=${local.base_url}
      (and pass your auth_token as the bearer credential if you set one).
    EOT

    langchain = <<-EOT
      pip install securevector-sdk-langchain
      export SECUREVECTOR_BASE_URL=${local.base_url}

      # in your agent:
      from securevector_sdk_langchain import secure_middleware
      from langchain.agents import create_agent
      agent = create_agent(model, tools, middleware=[secure_middleware(mode="enforce")])
    EOT

    langgraph = <<-EOT
      pip install securevector-sdk-langgraph
      export SECUREVECTOR_BASE_URL=${local.base_url}

      # in your agent:
      from securevector_sdk_langgraph import secure_middleware
      from langchain.agents import create_agent
      agent = create_agent(model, tools, middleware=[secure_middleware(mode="enforce")])
    EOT

    crewai = <<-EOT
      pip install securevector-sdk-crewai
      export SECUREVECTOR_BASE_URL=${local.base_url}

      # wrap your crew's tools with the SecureVector guard before kickoff.
      from securevector_sdk_crewai import secure_tools
      crew = Crew(agents=agents, tasks=tasks, tools=secure_tools(tools, mode="enforce"))
    EOT

    claude-code = <<-EOT
      # Point the SecureVector Claude Code plugin at this shared engine:
      export SECUREVECTOR_BASE_URL=${local.base_url}
      # (set your auth_token as the bearer credential in the plugin config).
    EOT

    cursor = <<-EOT
      # Point the SecureVector Cursor plugin at this shared engine:
      export SECUREVECTOR_BASE_URL=${local.base_url}
      # (set your auth_token as the bearer credential in the plugin config).
    EOT

    codex = <<-EOT
      # Point the SecureVector Codex plugin at this shared engine:
      export SECUREVECTOR_BASE_URL=${local.base_url}
      # (set your auth_token as the bearer credential in the plugin config).
    EOT
  }

  runtime_snippet = lookup(local.runtime_snippets, var.securevector_runtime, local.runtime_snippets["none"])
}

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

output "runtime_snippet" {
  description = "Copy-paste snippet wiring the chosen SecureVector SDK/plugin (var.securevector_runtime) to this engine."
  value       = local.runtime_snippet
}
