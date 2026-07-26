# GitHub Actions OIDC bootstrap

This root declares the account's GitHub OIDC provider and a role trusted only for one repository
and one exact Git ref. Its inline policy is limited to reading and writing a single OpenTofu state
object and managing that object's native S3 lock file.

Real inputs belong in `config/local/oidc.tfvars`, which is ignored:

```hcl
github_repository = "owner/repository"
github_ref        = "refs/heads/oidc-check"
state_bucket_name = "replace-with-a-globally-unique-bucket-name"
```

From this directory, review a saved plan before requesting the fresh human approval required for
the IAM and OIDC mutations:

```sh
tofu init
tofu plan -var-file=../../config/local/oidc.tfvars -out=oidc.tfplan
tofu show -json oidc.tfplan | ../../scripts/cost-guard.sh /dev/stdin
```

After an approved apply, store the `github_actions_role_arn` output as the non-secret repository
variable `AWS_OIDC_ROLE_ARN`. Publishing `.github/workflows/aws-identity.yml` requires its own fresh
approval. Run that workflow from the exact ref supplied as `github_ref`.

For the mandatory negative check, change `github_repository` to a different repository, obtain
fresh approval for the trust-policy mutation, apply it, and rerun the workflow. The credential
configuration step must fail. Restore the intended repository only after another fresh approval.
