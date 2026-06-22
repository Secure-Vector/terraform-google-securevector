# Free-tier example — SecureVector on Cloud Run

The lowest-commitment way to try the SecureVector engine: scale-to-zero Cloud
Run, a public HTTPS URL gated by a bearer token, and a `terraform destroy` that
leaves nothing behind.

```bash
terraform init
terraform apply \
  -var="project_id=YOUR_PROJECT" \
  -var="auth_token=$(openssl rand -hex 24)"

# grab the wired LangChain snippet:
terraform output -raw runtime_snippet

# when you're done:
terraform destroy -var="project_id=YOUR_PROJECT" -var="auth_token=ignored"
```

> Cost note: with `min_instances = 0` the service costs ~nothing at idle — you
> pay only for requests. `bucket_force_destroy = true` lets the audit bucket be
> removed on destroy so a trial leaves zero billable resources.
