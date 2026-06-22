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
- Application-layer credential (`securevector_api_key`) — an API key or minted
  `svet_`/`svpk_` token the engine requires and every client forwards via
  `SECUREVECTOR_API_KEY` (`Authorization: Bearer`, bearer optional) — plus a
  public-ingress toggle (`allow_unauthenticated`).
- Optional Cloud Connect bridge (`cloud_connect_token`) to enroll the node into
  the SecureVector managed fleet.
- `securevector_runtime` variable that emits a copy-paste SDK/plugin wiring
  snippet as a Terraform output, pre-pointed at the new dashboard URL. Covers
  all SecureVector clients: SDKs (langchain / langgraph / crewai) and plugins
  (claude-code / cursor / codex / copilot-cli / openclaw), each with its real
  base-URL env var (`SECUREVECTOR_SDK_APP_URL` for SDKs; `SV_BASE_URL` /
  `SECUREVECTOR_URL` for plugins) and the shared credential `SECUREVECTOR_API_KEY`
  every client forwards.
- Shared `runtime.tf` holding the supported-client contract, kept byte-identical
  across all `terraform-<cloud>-securevector` repos so every cloud exposes the
  same clients/snippets.
- Required-API enablement (`run.googleapis.com`, `storage.googleapis.com`).

### Fixed / hardened (Terraform best-practices review)
- **Correctness:** force `EXECUTION_ENVIRONMENT_GEN2` when persistence is on —
  GCS (gcsfuse) volume mounts require gen2, so the default `enable_persistence
  = true` would otherwise fail at apply. Added `execution_environment` override.
- Added a `/health` startup probe so Cloud Run waits for the engine to boot
  before routing (no 503s on cold start).
- `deletion_protection` is now a variable (default false for trials).
- Input validation on `container_port` (1–65535), `min_instances` (≥0),
  `max_instances` (≥1), `execution_environment` (enum).
- README: Option 1 (device-level engine) vs Option 2 (+ fleet & advanced cloud
  ML) made explicit; fixed stale `/data` / `securevector_api_key` references.

### Added (inbound auth)
- `ingress_token` variable → `SECUREVECTOR_INGRESS_TOKEN`. App-layer inbound
  gate: when set, the engine requires `Authorization: Bearer` / `X-Api-Key` on
  every request (`/health` stays open), validated by the new `ingress_auth`
  middleware in securevector-ai-threat-monitor (fail-open when unset). Pairs
  with or replaces Cloud Run IAM. Header-capable clients (OpenClaw, curl) can
  authenticate today; SDK/JS-hook client-side forwarding is rolling out (#182).

### Changed (DevOps review — aligned to the real app interface)
- Container env now uses only vars the app actually reads (verified against
  securevector-ai-threat-monitor): dropped the invented `SECUREVECTOR_HOST` /
  `SECUREVECTOR_PORT` / `SECUREVECTOR_DATA_DIR` / `SECUREVECTOR_CLOUD_CONNECT_TOKEN`.
- Host/port are CLI args (`--host`/`--port`), not env — added `container_command`
  (default defers to the image entrypoint, which must bind `0.0.0.0:container_port`).
- `securevector_api_key` reframed as the engine's **outbound** cloud key
  (`SECUREVECTOR_API_KEY` → `X-Api-Key`), **not** an inbound gate.
- `cloud_connect_token` now passed as `SECUREVECTOR_ENROLL_TOKEN` (svet_* org
  enroll → fleet + policy sync); requires the image entrypoint to run
  `securevector-app enroll`.
- Persistence mounts at `persistence_mount_path` (the app's real data dir
  `$HOME/.local/share/securevector/threat-monitor`) instead of `/data`; the app
  has no data-dir env override.
- README: added a pre-release status banner; corrected auth (no inbound gate
  today — Cloud Run IAM only) and a token→capability matrix.

### Notes
- Hard prerequisites (story #182): a published engine container image (no app
  Dockerfile / ghcr CI exists yet) whose entrypoint binds `0.0.0.0:$PORT`,
  stores data at the mount path, and enrolls from `SECUREVECTOR_ENROLL_TOKEN`;
  plus engine-side inbound auth. The Terraform is correct against the real app
  interface and will deploy a working engine once that image ships.
