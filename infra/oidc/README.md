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
tofu show -json oidc.tfplan | ../../scripts/cost-guard.sh /dev/stdin
```

After an approved apply, store the `github_actions_role_arn` output as the repository secret
`AWS_OIDC_ROLE_ARN`. Store the bucket name and immutable repository claim as the repository secrets
`AWS_STATE_BUCKET_NAME` and `AWS_GITHUB_REPOSITORY`. Publishing either AWS workflow requires its own
fresh approval. Run the identity workflow from the exact ref supplied as `github_ref`.

For the mandatory negative check, change `github_repository` to a different repository, obtain
fresh approval for the trust-policy mutation, apply it, and rerun the workflow. The credential
configuration step must fail. Restore the intended repository only after another fresh approval.
