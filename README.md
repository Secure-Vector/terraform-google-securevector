# terraform-google-securevector

[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)
[![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.5-7B42BC)](https://www.terraform.io/)
[![Cloud Run](https://img.shields.io/badge/Google%20Cloud-Run-4285F4)](https://cloud.google.com/run)

> **One `terraform apply` → a live, HTTPS SecureVector engine in your own Google
> Cloud project, in ~5 minutes.** The turnkey *server* companion to the
> SecureVector Guard SDKs ([langchain](https://pypi.org/project/securevector-sdk-langchain/) ·
> [langgraph](https://pypi.org/project/securevector-sdk-langgraph/) ·
> [crewai](https://pypi.org/project/securevector-sdk-crewai/)). The SDKs secure
> one agent on one laptop; this stands up the shared engine your whole team's
> agents, CI runners, and prod services point at.

This is **bring-your-own-cloud (BYOC) self-hosting**: the engine and all scanned
data live in *your* tenant, on *your* account — nothing leaves. It is the
local-first story scaled from one laptop to one shared box you control.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://ssh.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/Secure-Vector/terraform-google-securevector&cloudshell_working_dir=examples/free-tier)

---

## Why Cloud Run

Cloud Run gives **managed HTTPS, a public URL, and scale-to-zero** out of the
box — so the whole deployment is a handful of resources with no VPC, load
balancer, or manual TLS. Cheapest substrate to try, cleanest to tear down.

```
terraform apply -var="project_id=my-proj" -var="securevector_runtime=langchain"
#
# Outputs:
#   dashboard_url   = "https://securevector-xxxx-uc.a.run.app"
#   runtime_snippet = "pip install securevector-sdk-langchain  +  wired middleware"
```

## Quick start

### Prerequisites
- A Google Cloud project and `gcloud` authenticated (or use Cloud Shell — link above).
- Terraform `>= 1.5` (or OpenTofu).
- Permission to enable APIs and create Cloud Run / Storage resources in the project.

### Use as a module

```hcl
module "securevector" {
  source  = "Secure-Vector/securevector/google"
  version = "~> 0.1"   # once published to the Terraform Registry

  project_id           = "my-project"
  region               = "us-central1"
  securevector_runtime = "langchain"             # emits a wired client snippet
  auth_token           = var.securevector_token  # app-layer bearer gate
}

output "dashboard_url"   { value = module.securevector.dashboard_url }
output "runtime_snippet" { value = module.securevector.runtime_snippet }
```

Until the Registry listing is live, point `source` at the repo:
`source = "github.com/Secure-Vector/terraform-google-securevector"`.

The fastest path is the [`examples/free-tier`](examples/free-tier) example —
scale-to-zero, public URL, clean teardown.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | string | — (required) | GCP project to deploy into. |
| `region` | string | `us-central1` | Cloud Run region. |
| `name` | string | `securevector` | Service / resource base name. |
| `image` | string | `ghcr.io/secure-vector/securevector-ai-threat-monitor:latest` | Engine container image. Pin a tag for prod. |
| `container_port` | number | `8741` | Port the engine listens on. |
| `cpu` / `memory` | string | `1` / `512Mi` | Per-instance limits. |
| `min_instances` / `max_instances` | number | `0` / `2` | `0` = scale-to-zero. |
| `allow_unauthenticated` | bool | `true` | Public run.app URL (gated by `auth_token`). `false` = Google IAM only. |
| `auth_token` | string (sensitive) | `""` | App-layer bearer token. **Set this when public.** |
| `cloud_connect_token` | string (sensitive) | `""` | Optional Cloud Connect enrollment into the managed fleet. |
| `securevector_runtime` | string | `none` | Client to emit a wiring snippet for. SDKs: `langchain`/`langgraph`/`crewai`. Plugins: `claude-code`/`cursor`/`codex`/`copilot-cli`/`openclaw`. Or `none`. |
| `enable_persistence` | bool | `true` | Mount a GCS volume at `/data` for the audit hash-chain. |
| `persistence_bucket_name` | string | `""` | Override bucket name (default `<project>-<name>-data`). |
| `bucket_force_destroy` | bool | `false` | Let `destroy` delete a non-empty bucket (set `true` for trials). |
| `enable_apis` | bool | `true` | Enable required Google APIs. |
| `service_account_email` | string | `""` | Optional runtime service account. |
| `labels` | map(string) | `{}` | Labels on created resources. |
| `extra_env` | map(string) | `{}` | Extra container env vars. |

## Outputs

| Name | Description |
|---|---|
| `dashboard_url` | HTTPS URL of the engine dashboard. |
| `health_url` | Health endpoint for probes. |
| `service_name` / `region` | Deployed Cloud Run service identity. |
| `persistence_bucket` | Audit-chain bucket (null if persistence off). |
| `runtime_snippet` | Copy-paste snippet wiring the chosen SDK/plugin to this engine. |

## Clients — point any SDK or plugin at this engine

`securevector_runtime` makes the module emit a ready-to-paste wiring snippet
(`terraform output -raw runtime_snippet`). All SecureVector clients are
supported; the base-URL env var differs by family:

| Client | `securevector_runtime` value | Base-URL env var | Remote bearer auth |
|---|---|---|---|
| LangChain / LangGraph / CrewAI SDK | `langchain` / `langgraph` / `crewai` | `SECUREVECTOR_SDK_APP_URL` (+ `SECUREVECTOR_SDK_MODE`) | not yet (#182) |
| Claude Code plugin | `claude-code` | `SV_BASE_URL` (hooks) · `SECUREVECTOR_URL` (statusline) | not yet (#182) |
| Cursor plugin | `cursor` | `SV_BASE_URL` · `SECUREVECTOR_URL` | not yet (#182) |
| Codex plugin | `codex` | `SV_BASE_URL` · `SECUREVECTOR_URL` | not yet (#182) |
| GitHub Copilot CLI plugin | `copilot-cli` | `SV_BASE_URL` · `SECUREVECTOR_URL` | not yet (#182) |
| OpenClaw guard | `openclaw` | `SECUREVECTOR_URL` (+ `SECUREVECTOR_API_KEY`) | ✅ `Authorization: Bearer` |

(Plugin list mirrors `securevector-ai-threat-monitor/src/securevector/plugins/`.)

## Access & auth

The SecureVector engine is single-user by origin. v1 fronts it with an
**application-layer bearer token** (`auth_token`). When `allow_unauthenticated =
true`, Cloud Run serves the URL publicly over managed HTTPS and that token is
what gates access.

> **Remote-auth caveat (important).** Today **only the OpenClaw plugin forwards a
> bearer token** to a remote engine (via `SECUREVECTOR_API_KEY` →
> `Authorization: Bearer`). The three SDKs and the Claude Code / Cursor / Codex /
> Copilot CLI plugins can target a remote URL but **do not yet send an auth
> header**. Until first-class remote auth lands ([story #182](https://github.com/Secure-Vector/llm-security-engine/issues/182)),
> for those clients either:
> - set `allow_unauthenticated = false` and reach the service over Google IAM
>   (`gcloud run services proxy` / IAP), or
> - run with `auth_token = ""` on a private/network-restricted deployment.
>
> Set `auth_token` for an internet-reachable deployment **once the clients you
> use can authenticate** (OpenClaw can today).

> For production, consider sourcing `auth_token` / `cloud_connect_token` from
> Secret Manager rather than tfvars (roadmap; see open questions in the wiki).

## Persistence

`enable_persistence = true` mounts a GCS bucket at `/data` so the tamper-evident
audit hash-chain survives instance restarts. Note the gcsfuse/SQLite locking
caveat for highly concurrent writes — a managed-DB option is a planned uplift.
For a throwaway trial, set `enable_persistence = false` or
`bucket_force_destroy = true`.

## Cloud Connect (optional)

Set `cloud_connect_token` to enroll this self-hosted node into the SecureVector
managed fleet view — the OSS-self-host → paid Pro/Enterprise on-ramp. Leave it
empty to stay fully self-hosted with no outbound enrollment.

## Teardown

```bash
terraform destroy
```

Removes the Cloud Run service and (if `bucket_force_destroy = true`) the
persistence bucket. No leftover billable resources.

## Related

- **Client SDKs:** [`securevector-sdk-langchain`](https://github.com/Secure-Vector/securevector-sdk-langchain) · [`-langgraph`](https://github.com/Secure-Vector/securevector-sdk-langgraph) · [`-crewai`](https://github.com/Secure-Vector/securevector-sdk-crewai)
- **Other clouds:** `terraform-aws-securevector` · `terraform-azurerm-securevector` · `terraform-oci-securevector` — each ships the **identical** [`runtime.tf`](runtime.tf) (same supported clients, same env-var contract, same auth caveat). That file is the single source of truth for the client list and is kept byte-identical across all four cloud repos.
- **Engine source / container:** [`securevector-ai-threat-monitor`](https://github.com/Secure-Vector/securevector-ai-threat-monitor)

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for trademark attributions.
