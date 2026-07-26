#!/usr/bin/env bash
# Reject resource creations that are outside the foundation's zero-cost palette.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <opentofu-plan.json>\n' "$0" >&2
  exit 2
fi

plan_file=$1
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
denylist_file="${script_dir}/../config/cost-guard-denylist.json"

if [[ ! -f "$plan_file" ]]; then
  printf 'Plan file not found: %s\n' "$plan_file" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'cost-guard requires jq to read OpenTofu plan JSON.\n' >&2
  exit 2
fi

# A replacement has both delete and create actions. It is still a creation and must
# be denied, so match any change whose actions include "create".
denied=$(jq -r --slurpfile denylist "$denylist_file" '
  ($denylist[0] | INDEX(.resource_type)) as $denied_types
  | .resource_changes[]?
  | select((.change.actions // []) | index("create"))
  | select($denied_types[.type] != null)
  | "Denied resource: \(.address // .type) (\($denied_types[.type].resource)): \($denied_types[.type].monthly_cost)"
' "$plan_file")

if [[ -n "$denied" ]]; then
  printf '%s\n' "$denied" >&2
  exit 1
fi
