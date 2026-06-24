# EU-region example (GCP)

Deploys the SecureVector engine into an **EU Cloud Run region** for data residency. Identical to [`../free-tier`](../free-tier) except `region` is set to `europe-west1`.

```bash
terraform init
terraform apply -var="project_id=YOUR_PROJECT" -var="securevector_api_key=$(openssl rand -hex 24)"
terraform output -raw runtime_snippet
terraform destroy
```

Change `region` in `main.tf` to another EU region (e.g. `europe-west4`) if you prefer.

## Data residency

Both resources this module creates — the Cloud Run service and its GCS persistence bucket — live in the `region` set above. The engine processes and stores agent activity, threats, tool-audit, and governance data **only in your own GCP project and region**. SecureVector does not receive that data, and this module does not replicate it to any other region.

If you later enable Cloud Connect to view your governance posture in the SecureVector cloud, only metadata + hashes (never raw text) are forwarded, and only after you explicitly accept the governance terms. Keeping the deployment in an EU region keeps the resident copy of your data in the EU.
