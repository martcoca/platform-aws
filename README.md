# foundation
0002 Foundation — a cloud that cannot cost money

## Which account this repository targets

**Activate the profile before running anything against the cloud:**

```bash
export AWS_PROFILE=martcoca
```

The workstation carries credentials for more than one account, and the active one is
whichever was used last. Enumerate before selecting — never take the CLI's current default as
the account this repository belongs to. `doctrine/shared/cloud.md` has the enumeration
command for each provider and the reason this is written down: a chief-of-staff once reasoned
from the wrong account all the way to "the landing zone was never applied", when it had been
live for weeks under a named configuration.

The account and project identifiers themselves are **not recorded here** — they are
identifiers and stay out of tracked files. The profile name is a label on a workstation, not
an identifier, so it can be.

