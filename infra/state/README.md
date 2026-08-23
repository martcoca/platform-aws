# OpenTofu state bucket

This bootstrap root creates the S3 bucket used by `infra/oidc/`. The bucket has versioning,
S3-managed encryption, all public-access controls enabled, and destruction protection.

The bucket must exist before an S3 backend can use it, so this root is initialized with the local
backend. Its ignored local state is bootstrap state; the operational `infra/oidc/` state is migrated
into the bucket after the approved bucket creation.

Keep the globally unique bucket name in `config/local/state.tfvars`:

```hcl
state_bucket_name = "replace-with-a-globally-unique-bucket-name"
```

Review the plan before requesting the fresh human approval required to create the bucket:

```sh
tofu init
tofu plan -var-file=../../config/local/state.tfvars -out=state.tfplan
tofu show -json state.tfplan >state.plan.json
```

The cost guard is not a script in this repository; see `infra/oidc/README.md` for how to
run the pinned released action's guard against a saved plan file by hand.
