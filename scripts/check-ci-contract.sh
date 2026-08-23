#!/usr/bin/env bash
# Mechanically hold the CI safety contract: the cost guard is consumed, not carried, and
# it is still a gate rather than a decoration.
#
# Everything asserted here is invisible from a diff of any single file. A guard step can
# be deleted, excused with continue-on-error, unpinned to a branch, moved after an apply,
# or quietly replaced by a re-vendored local copy — and each of those leaves a workflow
# that still reads as guarded. Pull requests here merge without a human reading the diff,
# so these have to be checks rather than review habits.
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

workflow=.github/workflows/aws-plan.yml
demo=.github/workflows/cost-guard.yml

require() {
  local needle=$1 file=$2
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'Missing required contract text in %s: %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

require_absent() {
  local pattern=$1 file=$2
  if grep -Eq -- "$pattern" "$file"; then
    printf 'Forbidden contract text in %s: %s\n' "$file" "$pattern" >&2
    exit 1
  fi
}

# The block of one step, from its `- name:` line to the next step at the same indent.
# Used to scope an assertion to a single step: "no continue-on-error" is true of the
# guard step and deliberately false of the comment step, so a file-wide grep cannot
# express it.
step_block() {
  local file=$1 name=$2
  awk -v want="      - name: ${name}" '
    $0 == want { in_block = 1; print; next }
    in_block && /^      - / { exit }
    in_block { print }
  ' "$file"
}

# The trigger block of a workflow, from `on:` to the next top-level key.
triggers_of() {
  awk '/^on:/{f=1;next} /^[a-zA-Z_-]+:/{f=0} f' "$1"
}

# --- the guard and its denylist are not in this repository ----------------------------

for gone in scripts/cost-guard.sh config/cost-guard-denylist.json; do
  if [[ -e "$gone" ]] || git ls-files --error-unmatch "$gone" >/dev/null 2>&1; then
    printf '%s is back. The guard travels with the action; a local copy is the\n' "$gone" >&2
    printf 'duplication that extracting it removed.\n' >&2
    exit 1
  fi
done

# --- the pin has exactly one source ---------------------------------------------------

pin_file=config/cost-guard-action.txt
[[ -f "$pin_file" ]] || {
  printf 'Missing %s: the cost-guard release pin has no single source.\n' "$pin_file" >&2
  exit 1
}
pin=$(tr -d '[:space:]' < "$pin_file")
if [[ ! "$pin" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+@v[0-9]+(\.[0-9]+\.[0-9]+)?$ ]]; then
  printf 'The cost-guard pin must be owner/repo@vN or owner/repo@vN.N.N, not: %s\n' "$pin" >&2
  exit 1
fi

# Every use of the action, in every workflow, must be that exact pin. A branch ref would
# let what is denied change with no commit in this repository.
guard_uses=0
while IFS= read -r used; do
  [[ -n "$used" ]] || continue
  guard_uses=$((guard_uses + 1))
  if [[ "$used" != "$pin" ]]; then
    printf 'Workflow uses %s but the pin in %s is %s.\n' "$used" "$pin_file" "$pin" >&2
    exit 1
  fi
done < <(grep -hEo 'uses:[[:space:]]*[A-Za-z0-9._-]+/cost-guard@[^[:space:]]+' \
  .github/workflows/*.yml | sed 's/uses:[[:space:]]*//')
if [[ "$guard_uses" -eq 0 ]]; then
  printf 'No workflow uses the cost-guard action.\n' >&2
  exit 1
fi

# --- the guarded plan hands the guard a file, and the guard still gates ---------------

require 'tofu plan -input=false -no-color -json' "$workflow"
require '>"$RUNNER_TEMP/tofu-plan.json" 2>"$RUNNER_TEMP/tofu-plan.err"' "$workflow"
require "uses: ${pin}" "$workflow"
require 'plan: ${{ runner.temp }}/tofu-plan.json' "$workflow"
require 'id: cost-guard' "$workflow"
require 'GUARD_OUTCOME: ${{ steps.cost-guard.outcome }}' "$workflow"
require 'GUARD_VERDICT: ${{ steps.cost-guard.outputs.verdict }}' "$workflow"
require '[[ "$GUARD_OUTCOME" == "success" ]] || exit 1' "$workflow"
for verdict in allow deny 'plan failure' undecidable; do
  require "echo \"${verdict}\" >>\"\$GITHUB_STEP_SUMMARY\"" "$workflow"
done

# The exit code must come from the guard step. Piping into the guard reports the last
# process in the pipeline, which reads a plan that never ran as a clean plan; recovering
# it through PIPESTATUS is the shape this repository used to carry.
require_absent 'cost-guard\.sh|/dev/stdin|PIPESTATUS' "$workflow"

# The guard step itself must have no failure excuse. This is scoped to the step rather
# than to the file: the pull-request comment step is allowed to fail, because a comment
# that does not post is not a plan that was not guarded.
guard_block=$(step_block "$workflow" 'Cost guard')
[[ -n "$guard_block" ]] || {
  printf 'No "Cost guard" step in %s. The plan is unguarded.\n' "$workflow" >&2
  exit 1
}
for required in "uses: ${pin}" 'id: cost-guard' 'plan: ${{ runner.temp }}/tofu-plan.json'; do
  if ! printf '%s\n' "$guard_block" | grep -Fq -- "$required"; then
    printf 'The "Cost guard" step in %s is missing: %s\n' "$workflow" "$required" >&2
    exit 1
  fi
done
if printf '%s\n' "$guard_block" | grep -q 'continue-on-error'; then
  printf 'The "Cost guard" step in %s carries continue-on-error.\n' "$workflow" >&2
  printf 'A guard that is allowed to fail is a workflow that looks guarded and is not.\n' >&2
  exit 1
fi

# And nowhere else in the file either, apart from that one comment step. This is done by
# line number rather than by subtracting the step's text, because `continue-on-error: true`
# is the same string wherever it appears — subtracting it would delete every occurrence and
# report a clean file.
comment_step='Publish the guard verdict on the pull request'
comment_start=$(grep -n "^      - name: ${comment_step}\$" "$workflow" | head -n 1 | cut -d: -f1)
[[ -n "$comment_start" ]] || {
  printf 'No "%s" step in %s.\n' "$comment_step" "$workflow" >&2
  exit 1
}
comment_end=$(awk -v s="$comment_start" 'NR > s && /^      - / { print NR - 1; found = 1; exit }
                                         END { if (!found) print NR }' "$workflow")
while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue
  line=${hit%%:*}
  if (( line < comment_start || line > comment_end )); then
    printf 'continue-on-error at %s:%s is outside the "%s" step.\n' \
      "$workflow" "$line" "$comment_step" >&2
    printf 'Only the comment may fail without failing the job.\n' >&2
    exit 1
  fi
done < <(grep -n 'continue-on-error' "$workflow")

# The guard must follow the plan, so no step that could change infrastructure can be
# inserted between them.
plan_line=$(grep -n 'tofu plan -input=false -no-color -json' "$workflow" | head -n 1 | cut -d: -f1)
guard_line=$(grep -n "uses: ${pin}" "$workflow" | head -n 1 | cut -d: -f1)
if [[ -z "$plan_line" || -z "$guard_line" || "$guard_line" -le "$plan_line" ]]; then
  printf 'The guard step must follow the plan step in %s.\n' "$workflow" >&2
  exit 1
fi

# Nothing here applies today, and these keep it that way.
if grep -nEi 'tofu[[:space:]]+(apply|destroy|import|taint|state[[:space:]]+(rm|mv|push))' "$workflow" >/dev/null; then
  printf 'The guarded plan workflow must not change infrastructure.\n' >&2
  exit 1
fi
if grep -Eqi 'tofu[[:space:]]+apply|terraform[[:space:]]+apply' .github/workflows/*.yml; then
  printf 'Workflows must not apply infrastructure.\n' >&2
  exit 1
fi

# --- triggers: no workflow acquires a pull_request trigger it did not have -------------
#
# A pull_request trigger runs a workflow against code from the pull request. The three
# below already had one before the guard was extracted; the other two must not gain one
# by being edited near a workflow that has it.
for wf in aws-plan.yml cost-guard.yml guard.yml; do
  if ! triggers_of ".github/workflows/$wf" | grep -q '^[[:space:]]*pull_request:'; then
    printf '%s lost its pull_request trigger.\n' "$wf" >&2
    exit 1
  fi
done
for wf in aws-identity.yml auto-merge.yml; do
  if triggers_of ".github/workflows/$wf" | grep -q '^[[:space:]]*pull_request:'; then
    printf '%s gained a pull_request trigger it did not have.\n' "$wf" >&2
    exit 1
  fi
done

# --- the demonstration that the consumed action behaves like the deleted local one -----

require 'permissions:' "$demo"
require 'contents: read' "$demo"
require "uses: ${pin}" "$demo"
# The three exit outcomes, asserted through the action. `undecidable` failing rather than
# passing is the property most easily lost behind a wrapper, so it is named here rather
# than implied.
require "assert 'clean plan'          'success/allow/0'" "$demo"
require "assert 'denied create'       'failure/deny/1'" "$demo"
require "assert 'errored plan'        'failure/undecidable/2'" "$demo"
require "assert 'unrecognizable'      'failure/undecidable/2'" "$demo"
require "assert 'empty plan'          'failure/undecidable/2'" "$demo"

printf 'CI contract checks passed.\n'
