# terraform-google-securevector

[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)
[![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.5-7B42BC)](https://www.terraform.io/)
[![Cloud Run](https://img.shields.io/badge/Google%20Cloud-Run-4285F4)](https://cloud.google.com/run)

> **One `terraform apply` → a live, HTTPS SecureVector engine in your own Google
> Cloud project, in ~5 minutes.** The turnkey *server* companion to the
> SecureVector Guard SDKs ([langchain](https://pypi.org/project/securevector-sdk-langchain/) ·
> [langgraph](https://pypi.org/project/securevector-sdk-langgraph/) ·
> [crewai](https://pypi.org/project/securevector-sdk-crewai/)) **and the Guard
> plugins** for agent runtimes (Claude Code, Codex, GitHub Copilot CLI, OpenClaw,
> and more — see the
> [threat-monitor repo](https://github.com/Secure-Vector/securevector-ai-threat-monitor)).
> The SDKs and plugins secure individual agents on individual machines; this
> stands up the shared engine your whole team's agents, CI runners, and prod
> services point at.

This is **bring-your-own-cloud (BYOC) self-hosting**: the engine and all scanned
data live in *your* tenant, on *your* account — nothing leaves. It is the
local-first story scaled from one laptop to one shared box you control.

> ✅ **Status: live.** The engine image is published and **public** —
> `ghcr.io/secure-vector/securevector-ai-threat-monitor` (tags `latest` and
> `4.7.1`), multi-arch (amd64/arm64). `var.image` pulls it with no extra setup.
>
> One caveat: the current image runs **device-level (Option 1) detection**;
> engine-side **inbound auth** (`ingress_token` → `SECUREVECTOR_INGRESS_TOKEN`)
> is not yet enforced and ships in a later release. Until then, gate
> internet-facing deployments at the **network layer**
> (`allow_unauthenticated = false`, `ingress_cidrs`, or cloud IAM) rather than
> relying on `ingress_token` alone.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://ssh.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/Secure-Vector/terraform-google-securevector&cloudshell_working_dir=examples/free-tier)

---

## Why Cloud Run

Cloud Run gives **managed HTTPS, a public URL, and scale-to-zero** out of the
box — so the whole deployment is a handful of resources with no VPC, load
balancer, or manual TLS. Cheapest substrate to try, cleanest to tear down.

```
terraform apply -var="project_id=my-proj"
#
# Outputs:
#   dashboard_url   = "https://securevector-xxxx-uc.a.run.app"   # live, public, managed TLS
#   runtime_snippet = "point any SecureVector SDK/plugin at the URL above"
```

## Quick start

### Prerequisites
- A Google Cloud project and `gcloud` authenticated (or use Cloud Shell — link above).
- Terraform `>= 1.5` (or OpenTofu).
- Permission to enable APIs and create Cloud Run / Storage resources in the project.

There are two ways to run it. **Option 1** is the standalone self-host engine;
**Option 2** adds the SecureVector cloud on top.

| | **Option 1 — Device-level engine** (default) | **Option 2 — + Fleet & advanced cloud ML** |
|---|---|---|
| What you get | Your own engine doing **local, device-level** detection — local rules + the **Guardian ML** model — running entirely in your tenant. | Everything in Option 1, **plus** the SecureVector cloud: org **fleet** management, **policy sync**, and the cloud's **advanced ML / enhanced `/analyze`**. |
| Needs | Just a GCP project. No SecureVector account. | **Requires a SecureVector account (sign up).** An `svet_*` enrollment token (and/or `svpk_*` key); cloud tiers/billing apply. |
| Set | nothing extra | `cloud_connect_token` (svet\_) and/or `securevector_api_key` (svpk\_) |

#### Option 1 — Device-level engine (default, one command)

Just a project ID: scale-to-zero Cloud Run, a public HTTPS URL, local detection,
and a clean `terraform destroy`. This is the [`examples/free-tier`](examples/free-tier) example.

```bash
terraform apply -var="project_id=my-project"
terraform output dashboard_url      # live HTTPS URL — local engine, device-level detection
terraform destroy                   # clean teardown, no leftover billing
```

> Keyless = the endpoint is open. Fine for a quick trial or a
> private/network-restricted box. For anything internet-facing, gate it with
> `ingress_token` (app-layer auth) and/or `allow_unauthenticated = false` (IAM).

#### Option 2 — Add fleet management + advanced cloud ML

> **Requires a SecureVector account — sign up first.** Option 2 connects the
> engine to the SecureVector cloud, so you must create an account and obtain a
> token: an `svet_*` enrollment token (→ fleet + policy sync) and/or an `svpk_*`
> key (→ personal cloud mode). Sign up at [app.securevector.io/signup](https://app.securevector.io/signup).
> Cloud tiers / billing apply. **Option 1 needs none of this.**

Same engine, now bridged to the SecureVector cloud: set `cloud_connect_token`
(an `svet_*` org token → **fleet view + policy sync**) and/or
`securevector_api_key` (a personal `svpk_*`/legacy key → personal cloud mode +
**enhanced ML `/analyze`**). Those are the engine's *outbound* cloud credentials.
Add `ingress_token` to authenticate inbound clients. See
[Tokens](#tokens--which-credential-enables-what).

**Fleet use case — one pane of glass across many containers.** Running more than
one engine — replicas of a service, several agent apps, or containers spread
across regions and clusters? Give every container the **same**
`cloud_connect_token` (`svet_*`). Each node enrolls into your org and streams its
**security findings** (threats, blocked tool calls, secret/data-leak hits) and
**observability** (agent runs, tool-permission decisions) up to the SecureVector
cloud — so the **entire fleet shows up in a single span / fleet view** instead of
N isolated per-container dashboards. One place to watch security posture *and*
agent behavior across the whole fleet, with org-wide policy pushed back down to
every node via policy sync.

```hcl
module "securevector" {
  source  = "Secure-Vector/securevector/google"
  version = "~> 0.1"   # once published to the Terraform Registry

  project_id            = "my-project"
  region                = "us-central1"
  securevector_runtime  = "langchain"            # emits a wired client snippet
  ingress_token         = var.ingress_token      # app-layer inbound auth
  cloud_connect_token   = var.svet_token         # → fleet + policy sync (advanced)
  # securevector_api_key = var.svpk_key          # → personal cloud mode + enhanced ML
  # allow_unauthenticated = false                # or/also gate at the network layer (IAM)
}

output "dashboard_url"   { value = module.securevector.dashboard_url }
output "runtime_snippet" { value = module.securevector.runtime_snippet }
```

Until the Registry listing is live, point `source` at the repo:
`source = "github.com/Secure-Vector/terraform-google-securevector"`.

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
| `container_command` | list(string) | `[]` | Override the image entrypoint. `[]` = use the image's own. App takes host/port as CLI args. |
| `allow_unauthenticated` | bool | `true` | Public run.app URL (network layer). Pair with `ingress_token`, or set `false` to require Google IAM. |
| `ingress_token` | string (sensitive) | `""` | App-layer inbound gate → `SECUREVECTOR_INGRESS_TOKEN`. When set, the engine requires `Authorization: Bearer`/`X-Api-Key`; `/health` stays open. |
| `securevector_api_key` | string (sensitive) | `""` | **Outbound** cloud key (`svpk_`/legacy) → `SECUREVECTOR_API_KEY` (personal cloud mode). Not an inbound gate. |
| `securevector_api_url` | string | `""` | Override the SecureVector cloud API base URL. |
| `cloud_connect_token` | string (sensitive) | `""` | **Outbound** `svet_*` org enroll token → `SECUREVECTOR_ENROLL_TOKEN` (fleet + policy sync). Needs the image entrypoint to enroll. |
| `securevector_runtime` | string | `none` | Client to emit a wiring snippet for. SDKs: `langchain`/`langgraph`/`crewai`. Plugins: `claude-code`/`cursor`/`codex`/`copilot-cli`/`openclaw`. Or `none`. |
| `enable_persistence` | bool | `true` | Mount a GCS volume for the audit hash-chain. |
| `persistence_mount_path` | string | `…/securevector/threat-monitor` | Where the volume mounts; must equal the app data dir in the image. |
| `persistence_bucket_name` | string | `""` | Override bucket name (default `<project>-<name>-data`). |
| `bucket_force_destroy` | bool | `false` | Let `destroy` delete a non-empty bucket (set `true` for trials). |
| `enable_apis` | bool | `true` | Enable required Google APIs. |
| `execution_environment` | string | `""` | `""` auto-picks GEN2 when persistence is on (required for GCS volumes); or pin GEN1/GEN2. |
| `deletion_protection` | bool | `false` | Cloud Run deletion protection. `true` to protect a production service. |
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
supported. **The base-URL env var (how a client targets the engine) differs by
family** and is the part that works today:

| Client | `securevector_runtime` value | Base-URL env var (targets the engine) |
|---|---|---|
| LangChain / LangGraph / CrewAI SDK | `langchain` / `langgraph` / `crewai` | `SECUREVECTOR_SDK_APP_URL` (+ `SECUREVECTOR_SDK_MODE`) |
| Claude Code plugin | `claude-code` | `SV_BASE_URL` (hooks) · `SECUREVECTOR_URL` (statusline) |
| Cursor plugin | `cursor` | `SV_BASE_URL` · `SECUREVECTOR_URL` |
| Codex plugin | `codex` | `SV_BASE_URL` · `SECUREVECTOR_URL` |
| GitHub Copilot CLI plugin | `copilot-cli` | `SV_BASE_URL` · `SECUREVECTOR_URL` |
| OpenClaw guard | `openclaw` | `SECUREVECTOR_URL` |

When the module sets `ingress_token`, the engine **requires** a credential
(`Authorization: Bearer` / `X-Api-Key`). A client forwards it via
`SECUREVECTOR_API_KEY` — **OpenClaw (and any header-capable client like curl)
works today**; SDK / JS-hook client-side forwarding is rolling out, so for
those leave `ingress_token` unset or use Cloud Run IAM. (Plugin list mirrors
`securevector-ai-threat-monitor/src/securevector/plugins/`.)

## Tokens — which credential enables what

Two distinct, **outbound** engine credentials (engine → SecureVector cloud), plus
the inbound story:

| Capability | Direction | Credential | Notes |
|---|---|---|---|
| **Remote analyze** (client → engine) | inbound | `ingress_token` → `SECUREVECTOR_INGRESS_TOKEN` | Engine requires `Authorization: Bearer`/`X-Api-Key` when set (fail-open when unset). Header-capable clients (OpenClaw, curl) work today; SDK/JS-hook forwarding rolling out. Or use Cloud Run IAM. |
| **Personal cloud mode** (enhanced detection) | outbound | `securevector_api_key` (`svpk_`/legacy) → `SECUREVECTOR_API_KEY` | Engine presents it to the cloud as `X-Api-Key` (`cloud_sync.py`). No policy sync. |
| **Forward to fleet** (org visibility) | outbound | `cloud_connect_token` (`svet_*`) → `SECUREVECTOR_ENROLL_TOKEN` | Org enrollment. Needs the image entrypoint to run `securevector-app enroll`. |
| **Sync policies to local** (signed bundles) | outbound→in | `cloud_connect_token` (`svet_*` **only**) | `svpk_`/legacy/none ⇒ Policy Sync OFF — no partial mode (`device_admin.py`). |

> For production, source `securevector_api_key` / `cloud_connect_token` from
> Secret Manager rather than tfvars (roadmap; see wiki open questions).

## Persistence

`enable_persistence = true` mounts a GCS bucket for the tamper-evident audit
hash-chain. The app has **no data-dir env override** — it writes to
`$HOME/.local/share/securevector/threat-monitor` — so `persistence_mount_path`
must equal that path in the published image (the image must run as a user whose
`$HOME` maps there). Note the gcsfuse/SQLite locking caveat for highly concurrent
writes — a managed-DB option is a planned uplift. For a throwaway trial, set
`enable_persistence = false` or `bucket_force_destroy = true`.

## Cloud Connect (optional)

Set `cloud_connect_token` (an `svet_*` org enrollment token) to enroll this
self-hosted node into the SecureVector managed fleet view and receive signed
policy bundles — the OSS-self-host → paid Pro/Enterprise on-ramp. It is passed
as `SECUREVECTOR_ENROLL_TOKEN`; the published image's entrypoint must run
`securevector-app enroll` (then serve) for it to take effect. Leave empty to stay
fully self-hosted with no outbound enrollment.

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
