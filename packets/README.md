# Packets

Work in this repository is defined by packets. A packet states a Goal, a Boundary, a
Check, and enough context to execute without reading another repository.

## Working order

| # | Packet | Status | Is |
|---|---|---|---|
| 1 | [`0010-E01-T03.md`](0010-E01-T03.md) | done | Consume the released cost guard action and delete this repository's local copies |
| 2 | [`0010-E01-T07.md`](0010-E01-T07.md) | done | Anchor the contract check so a comment cannot satisfy an assertion about a real YAML line |
| 3 | [`0010-E02-T03.md`](0010-E02-T03.md) | done | Report when the cost guard pin is behind the current release, including on a schedule |

Take the packet the Founder names. Otherwise take the next one in this table whose
`Status:` is not `done`. The table is the order; the numbers are only identity.

This repository predates the packet convention; earlier work here is not listed.

## Rules

- **One packet in flight at a time.**
- **Never edit a packet body.** If it asks for the wrong thing, say so and stop. If a
  *step* is impossible but its intent is clear, do the nearest valid thing and say what you
  changed — stopping is for authority, not for difficulty.
- **You may set `Status:`** and nothing else in the file.
- **Run the Check yourself** before opening a pull request.
- **Write `evidence/<packet-id>.md`** in the same pull request: the Check output, what you
  verified, what you could not, and any decision the packet left to you. CI enforces it.
- **If you are blocked, open an issue labelled `blocked`.** A blocker mentioned only in
  conversation does not survive the conversation.
- **Branch, commit, open a pull request.** Never commit to `main`, never merge your own
  work. Auto-merge lands it when every check passes.
- **Stop at anything irreversible or cost-incurring** — cloud apply, provisioning,
  deletion, publishing, spend. You hold no such authority.

## If no packet applies

Stop and ask. The absence of a packet is information, not an invitation.
