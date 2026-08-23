# GitHub Actions OIDC bootstrap

This root declares the account's GitHub OIDC provider and a role trusted only for one repository's
configured ref and pull-request workflows. Its inline policy can read the identity resources it
plans, read and write one OpenTofu state object, and manage that object's native S3 lock file.

Real inputs belong in `config/local/oidc.tfvars`, which is ignored:

```hcl
github_repository = "owner/repository"
github_ref        = "refs/heads/oidc-check"
state_bucket_name = "replace-with-a-globally-unique-bucket-name"
```

Create the state bucket from `infra/state/` before initializing this root's backend. Then review a
saved plan before requesting the fresh human approval required for the IAM and OIDC mutations:

```sh
tofu init -migrate-state -backend-config="bucket=$TF_BACKEND_BUCKET"
tofu plan -var-file=../../config/local/oidc.tfvars -out=oidc.tfplan
tofu show -json oidc.tfplan >oidc.plan.json
```

The cost guard is no longer a script in this repository: it travels with the pinned
composite action recorded in `config/cost-guard-action.txt`, and CI runs it that way. To
check a saved plan by hand, check that release out and run its guard against the plan
**file** — the guard takes a path, not a pipe, so its exit code is read from the guard and
not from the last process in a pipeline:

```sh
pin=$(cat ../../config/cost-guard-action.txt)
gh repo clone "${pin%@*}" /tmp/cost-guard -- --depth 1 --branch "${pin##*@}"
bash /tmp/cost-guard/scripts/cost-guard.sh oidc.plan.json   # 0 allow, 1 deny, 2 undecidable
```

After an approved apply, store the `github_actions_role_arn` output as the repository secret
`AWS_OIDC_ROLE_ARN`. Store the bucket name and immutable repository claim as the repository secrets
`AWS_STATE_BUCKET_NAME` and `AWS_GITHUB_REPOSITORY`. Publishing either AWS workflow requires its own
fresh approval. Run the identity workflow from the exact ref supplied as `github_ref`.

For the mandatory negative check, change `github_repository` to a different repository, obtain
fresh approval for the trust-policy mutation, apply it, and rerun the workflow. The credential
configuration step must fail. Restore the intended repository only after another fresh approval.
