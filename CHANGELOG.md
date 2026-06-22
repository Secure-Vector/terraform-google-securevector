# Changelog

All notable changes to this module are documented here. This project adheres to
[Semantic Versioning](https://semver.org/). The Terraform Registry publishes a
release per `vX.Y.Z` git tag.

## [Unreleased]

### Added
- Initial GCP Cloud Run module: deploys the SecureVector engine to the user's
  own Google Cloud project with managed HTTPS, scale-to-zero defaults, and a
  clean `terraform destroy`.
- Optional GCS-backed persistence volume (`/data`) for the tamper-evident audit
  hash-chain (`enable_persistence`, default on).
- Application-layer bearer-token gate (`auth_token`) and public-ingress toggle
  (`allow_unauthenticated`).
- Optional Cloud Connect bridge (`cloud_connect_token`) to enroll the node into
  the SecureVector managed fleet.
- `securevector_runtime` variable that emits a copy-paste SDK/plugin wiring
  snippet as a Terraform output, pre-pointed at the new dashboard URL. Covers
  all SecureVector clients: SDKs (langchain / langgraph / crewai) and plugins
  (claude-code / cursor / codex / copilot-cli / openclaw), each with its real
  env-var contract (`SECUREVECTOR_SDK_APP_URL` for SDKs; `SV_BASE_URL` /
  `SECUREVECTOR_URL` for plugins; `SECUREVECTOR_API_KEY` bearer for openclaw).
- Shared `runtime.tf` holding the supported-client contract, kept byte-identical
  across all `terraform-<cloud>-securevector` repos so every cloud exposes the
  same clients/snippets.
- Required-API enablement (`run.googleapis.com`, `storage.googleapis.com`).

### Notes
- Depends on the public engine container image at
  `ghcr.io/secure-vector/securevector-ai-threat-monitor` and the app's
  documented "server mode" (see securevector-ai-threat-monitor, story #182).
