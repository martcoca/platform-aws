#!/usr/bin/env bash
# Mechanically hold the CI safety contract: the cost guard is consumed, not carried, and
# it is still a gate rather than a decoration.
#
# Everything asserted here is invisible from a diff of any single file. A guard step can
# be deleted, excused, unpinned to a branch, moved after an apply, or quietly replaced by
# a re-vendored local copy — and each of those leaves a workflow that still reads as
# guarded. Pull requests here merge without a human reading the diff, so these have to be
# checks rather than review habits.
#
# grep, not ripgrep. A `if rg ...` test fails *open* where ripgrep is absent: the shell
# returns 127, the branch is not taken, and a forbidden pattern is reported as clean. That
# is exactly backwards for a check whose job is to refuse.
set -euo pipefail

self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

# The self-test at the bottom re-runs this script against a throwaway tree. The child must
# not recurse, so it is invoked with --no-selftest. Nothing else changes behaviour: the
# flag skips the demonstration, never an assertion about this repository's workflows.
selftest_enabled=1
[[ "${1:-}" == "--no-selftest" ]] && selftest_enabled=0

workflow=.github/workflows/aws-plan.yml
demo=.github/workflows/cost-guard.yml

# Text that must appear *somewhere* in a file. Used only where the assertion really is
# about a string occurring, not about a line existing — see require_line below.
require() {
  local needle=$1 file=$2
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'Missing required contract text in %s: %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

# A fixed-string match is satisfied by a *comment*. Deleting the guard step but leaving a
# line of prose that names it passes `require` and leaves the workflow unguarded — the
# compromised file the obvious check waves through. Structural facts are therefore matched
# as whole YAML lines: a comment begins with `#` after its indent and cannot match.
require_line() {
  local regex=$1 file=$2
  if ! grep -Eq -- "^[[:space:]]*${regex}[[:space:]]*\$" "$file"; then
    printf 'Missing required contract line /%s/ in %s.\n' "$regex" "$file" >&2
    printf 'It must be a real YAML line, not a mention of one in a comment.\n' >&2
    exit 1
  fi
}

# The same, scoped to one step's block rather than to a whole file.
require_line_in() {
  local regex=$1 block=$2 label=$3 file=$4
  if ! printf '%s\n' "$block" | grep -Eq -- "^[[:space:]]*${regex}[[:space:]]*\$"; then
    printf 'The "%s" step in %s is missing the line /%s/.\n' "$label" "$file" "$regex" >&2
    printf 'It must be a real YAML line, not a mention of one in a comment.\n' >&2
    exit 1
  fi
}

# Forbidden text. Deliberately *not* anchored: for a rejection, matching a comment too is
# fail-closed. A commented-out pipeline is at worst a false refusal, and a false refusal is
# the safe direction for a gate.
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
# express it. The `- name:` match is line equality, so a commented-out step header does
# not open a block.
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

# The pin, escaped for use inside an extended regular expression.
pin_re() { printf '%s' "${1//./\\.}"; }

# --- the guard and its denylist are not in this repository ----------------------------
#
# Absent from the working tree *and* untracked. A file only deleted on disk but still
# tracked comes back on the next checkout.

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
pin_escaped=$(pin_re "$pin")

# Every use of the action, in every workflow, must be that exact pin. A branch ref would
# let what is denied change with no commit in this repository.
#
# Anchored as a whole line: an unanchored scanner cannot tell `uses: …@main` from a
# comment mentioning it, and refused a workflow whose guard was correctly pinned because
# someone had left a commented-out experiment above it.
#
# The pattern also has to admit a *sub-action* — `owner/cost-guard/freshness@ref` — because
# the freshness action lives in a subdirectory of the same repository and is the same
# release. The narrower pattern this replaced required `@` straight after `cost-guard`, so
# it matched none of the freshness lines and reported nothing about them: the freshness
# action could have sat on a different ref, or on `@main`, and this scanner would have said
# every use matched the pin. The comparison below is therefore on repository and ref, not
# on the whole string.
pin_repo="${pin%@*}"
pin_ref="${pin##*@}"
guard_uses=0
freshness_uses=0
while IFS= read -r used; do
  [[ -n "$used" ]] || continue
  used_path="${used%@*}"
  used_ref="${used##*@}"
  used_repo=$(printf '%s' "$used_path" | cut -d/ -f1,2)
  used_sub=$(printf '%s' "$used_path" | cut -d/ -f3-)
  guard_uses=$((guard_uses + 1))
  [[ -n "$used_sub" ]] && freshness_uses=$((freshness_uses + 1))
  if [[ "$used_repo" != "$pin_repo" || "$used_ref" != "$pin_ref" ]]; then
    printf 'Workflow uses %s but the pin in %s is %s.\n' "$used" "$pin_file" "$pin" >&2
    exit 1
  fi
done < <(grep -hE '^[[:space:]]*uses:[[:space:]]*[A-Za-z0-9._-]+/cost-guard(/[A-Za-z0-9._-]+)*@[^[:space:]]+[[:space:]]*$' \
  .github/workflows/*.yml | sed 's/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]*$//')
if [[ "$guard_uses" -eq 0 ]]; then
  printf 'No workflow uses the cost-guard action.\n' >&2
  exit 1
fi
if [[ "$freshness_uses" -eq 0 ]]; then
  printf 'No workflow uses the cost-guard freshness action.\n' >&2
  printf 'A consumer with no freshness signal cannot tell it is enforcing an old denylist.\n' >&2
  exit 1
fi
freshness_pin="${pin_repo}/freshness@${pin_ref}"
freshness_escaped=$(pin_re "$freshness_pin")

# --- the guarded plan hands the guard a file, and the guard still gates ---------------

# Text, not a line: the plan command ends in a `\` continuation, so it is half a line. The
# structural half of this assertion is the anchored ordering grep further down, which
# requires a real line beginning with the command and exits if there is none.
require 'tofu plan -input=false -no-color -json' "$workflow"

require_line '>"\$RUNNER_TEMP/tofu-plan\.json" 2>"\$RUNNER_TEMP/tofu-plan\.err"' "$workflow"
require_line "uses: ${pin_escaped}" "$workflow"
require_line 'plan: \$\{\{ runner\.temp \}\}/tofu-plan\.json' "$workflow"
require_line 'id: cost-guard' "$workflow"
require_line 'GUARD_OUTCOME: \$\{\{ steps\.cost-guard\.outcome \}\}' "$workflow"
require_line 'GUARD_VERDICT: \$\{\{ steps\.cost-guard\.outputs\.verdict \}\}' "$workflow"
require_line '\[\[ "\$GUARD_OUTCOME" == "success" \]\] \|\| exit 1' "$workflow"
for verdict in allow deny 'plan failure' undecidable; do
  require_line "echo \"${verdict}\" >>\"\\\$GITHUB_STEP_SUMMARY\"" "$workflow"
done

# The exit code must come from the guard step. Piping into the guard reports the last
# process in the pipeline, which reads a plan that never ran as a clean plan; recovering
# it out of the shell afterwards is the shape this repository used to carry. The three
# spellings are named as data rather than in prose, so this comment cannot satisfy the
# assertion it explains.
for laundered in 'cost-guard\.sh' '/dev/stdin' 'PIPESTATUS'; do
  require_absent "$laundered" "$workflow"
done

# The guard step itself must have no failure excuse. This is scoped to the step rather
# than to the file: the pull-request comment step is allowed to fail, because a comment
# that does not post is not a plan that was not guarded.
guard_block=$(step_block "$workflow" 'Cost guard')
[[ -n "$guard_block" ]] || {
  printf 'No "Cost guard" step in %s. The plan is unguarded.\n' "$workflow" >&2
  exit 1
}
require_line_in "uses: ${pin_escaped}" "$guard_block" 'Cost guard' "$workflow"
require_line_in 'id: cost-guard' "$guard_block" 'Cost guard' "$workflow"
require_line_in 'plan: \$\{\{ runner\.temp \}\}/tofu-plan\.json' "$guard_block" 'Cost guard' "$workflow"
if printf '%s\n' "$guard_block" | grep -q 'continue-on-error'; then
  printf 'The "Cost guard" step in %s carries continue-on-error.\n' "$workflow" >&2
  printf 'A guard that is allowed to fail is a workflow that looks guarded and is not.\n' >&2
  exit 1
fi

# And nowhere else in the file either, apart from that one comment step. This is done by
# line number rather than by subtracting the step's text, because `continue-on-error: true`
# is the same string wherever it appears — subtracting it would delete every occurrence and
# report a clean file. Unanchored, like every other rejection here: a commented-out excuse
# outside the comment step is refused too, which is the safe direction.
comment_step='Publish the guard verdict on the pull request'
comment_start=$(grep -n "^      - name: ${comment_step}\$" "$workflow" | head -n 1 | cut -d: -f1 || true)
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
# inserted between them. Both anchored to the start of a real line: a comment naming
# either one must not be able to establish the ordering.
#
# The `|| true` on each assignment is load-bearing. Under `pipefail` a grep that matches
# nothing fails the whole pipeline, and `set -e` then kills the script at the assignment —
# before the `if` below can say what was wrong. It still exits non-zero, so it fails
# closed, but a gate that refuses without saying why is a gate someone will disable.
plan_line=$(grep -nE '^[[:space:]]*tofu plan -input=false -no-color -json' "$workflow" | head -n 1 | cut -d: -f1 || true)
guard_line=$(grep -nE "^[[:space:]]*uses:[[:space:]]*${pin_escaped}[[:space:]]*\$" "$workflow" | head -n 1 | cut -d: -f1 || true)
if [[ -z "$plan_line" || -z "$guard_line" || "$guard_line" -le "$plan_line" ]]; then
  printf 'The guard step must follow the plan step in %s.\n' "$workflow" >&2
  exit 1
fi

# Nothing here applies today, and these keep it that way. Rejections, so unanchored.
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
# by being edited near a workflow that has it. Already anchored: `^[[:space:]]*pull_request:`
# cannot match a `#` comment in either direction.
for wf in aws-plan.yml cost-guard.yml guard.yml; do
  if ! triggers_of ".github/workflows/$wf" | grep -q '^[[:space:]]*pull_request:'; then
    printf '%s lost its pull_request trigger.\n' "$wf" >&2
    exit 1
  fi
done
for wf in aws-identity.yml auto-merge.yml cost-guard-freshness.yml; do
  if triggers_of ".github/workflows/$wf" | grep -q '^[[:space:]]*pull_request:'; then
    printf '%s gained a pull_request trigger it did not have.\n' "$wf" >&2
    exit 1
  fi
done

# --- the demonstration that the consumed action behaves like the deleted local one -----

require_line 'permissions:' "$demo"
require_line 'contents: read' "$demo"
require_line "uses: ${pin_escaped}" "$demo"
# The three exit outcomes, asserted through the action. `undecidable` failing rather than
# passing is the property most easily lost behind a wrapper, so it is named here rather
# than implied.
require_line "assert 'clean plan' +'success/allow/0' +\"\\\$CLEAN\"" "$demo"
require_line "assert 'denied create' +'failure/deny/1' +\"\\\$DENIED\"" "$demo"
require_line "assert 'errored plan' +'failure/undecidable/2' +\"\\\$ERRORED\"" "$demo"
require_line "assert 'unrecognizable' +'failure/undecidable/2' +\"\\\$UNRECOGNIZABLE\"" "$demo"
require_line "assert 'empty plan' +'failure/undecidable/2' +\"\\\$EMPTY\"" "$demo"

# --- the pin cannot be silently behind -------------------------------------------------
#
# Freshness is a separate signal with a separate failure mode, and the whole point of it is
# that it works when nobody is watching. Three things have to hold, and none is visible from
# one file: the step runs beside the guard even when the guard failed, it does not block
# unrelated work, and something reports staleness on a clock rather than on a push.

fresh=.github/workflows/cost-guard-freshness.yml
[[ -f "$fresh" ]] || {
  printf 'Missing %s: nothing reports a stale pin when nobody pushes.\n' "$fresh" >&2
  exit 1
}

# The pin is read from the file, never written as a literal into a `with:`. The pin file is
# the single source; a literal here would be a fourth place to update on a bump.
for f in "$workflow" "$fresh" "$demo"; do
  require_line 'id: pin' "$f"
  require_line 'printf .pin=%s\\n. "\$\(tr -d .\[:space:\]. < config/cost-guard-action\.txt\)" >>"\$GITHUB_OUTPUT"' "$f"
  require_line "uses: ${freshness_escaped}" "$f"
  require_line 'pin: \$\{\{ steps\.pin\.outputs\.pin \}\}' "$f"
done

# In the guarded plan: beside the guard, always run, and never blocking.
plan_freshness=$(step_block "$workflow" 'Cost guard freshness')
[[ -n "$plan_freshness" ]] || {
  printf 'No "Cost guard freshness" step in %s.\n' "$workflow" >&2
  printf 'The guarded plan would report a verdict without saying whether the guard is current.\n' >&2
  exit 1
}
require_line_in 'if: always\(\)' "$plan_freshness" 'Cost guard freshness' "$workflow"
require_line_in "uses: ${freshness_escaped}" "$plan_freshness" 'Cost guard freshness' "$workflow"
require_line_in "fail-on-stale: 'false'" "$plan_freshness" 'Cost guard freshness' "$workflow"
# Staleness must not turn an unrelated pull request red. This file runs on pull_request.
require_absent "fail-on-stale: 'true'" "$workflow"

# The freshness step must come after the guard step, so a denial is still the job's first
# and loudest failure rather than being preceded by a version complaint.
freshness_line=$(grep -nE "^[[:space:]]*uses:[[:space:]]*${freshness_escaped}[[:space:]]*\$" "$workflow" | head -n 1 | cut -d: -f1 || true)
if [[ -z "$freshness_line" || "$freshness_line" -le "$guard_line" ]]; then
  printf 'The freshness step must follow the guard step in %s.\n' "$workflow" >&2
  exit 1
fi

# On the clock, and only there, staleness is not ignorable.
require_line 'schedule:' "$fresh"
require_line "- cron: '17 6 \* \* \*'" "$fresh"
require_line 'workflow_dispatch:' "$fresh"
require_line 'contents: read' "$fresh"
require_line "fail-on-stale: 'true'" "$fresh"
require_line '\[\[ "\$STATUS" != "behind" \]\] \|\| exit 1' "$fresh"
# Nothing on a clock may touch infrastructure or a plan.
require_absent 'tofu|aws-actions/configure-aws-credentials' "$fresh"

# And the standing proof that a broken lookup changes no verdict.
require "assert 'clean plan, lookup broken'    'success/allow/0'" "$demo"
require "assert 'denied create, lookup broken' 'failure/deny/1'" "$demo"
require "assert 'freshness, no reachable API'  'success/unknown'" "$demo"
require_line 'GH_HOST: cost-guard-freshness\.invalid' "$demo"

# --- the check must be able to refuse -------------------------------------------------
#
# Everything above proves this repository is conformant. None of it proves the check would
# notice if it stopped being. Those are different claims, and only the first one is easy to
# get accidentally: a check whose assertions have all quietly stopped matching also reports
# success. So the last thing the check does is fail on purpose.
#
# It runs against a throwaway copy of the tree, never against the real one — a gate that
# edits the working tree to test itself is a worse problem than the one it is testing for.

selftest() {
  local tmp status out label
  tmp=$(mktemp -d)
  mkdir -p "$tmp/scripts" "$tmp/.github/workflows" "$tmp/config"
  cp "$self" "$tmp/scripts/check-ci-contract.sh"
  cp .github/workflows/*.yml "$tmp/.github/workflows/"
  cp "$pin_file" "$tmp/config/"

  # $1 label, $2 file to install as the plan workflow, $3 expected exit (0 or 1),
  # $4 substring the output must contain (empty when none is required).
  run_case() {
    label=$1
    cp "$2" "$tmp/.github/workflows/aws-plan.yml"
    set +e
    out=$(bash "$tmp/scripts/check-ci-contract.sh" --no-selftest 2>&1)
    status=$?
    set -e
    if [[ "$status" -ne "$3" ]]; then
      printf 'Self-test "%s": expected exit %s, got %s.\n' "$label" "$3" "$status" >&2
      printf '%s\n' "$out" >&2
      rm -rf "$tmp"
      exit 1
    fi
    if [[ -n "$4" ]] && [[ "$out" != *"$4"* ]]; then
      printf 'Self-test "%s": output did not mention %s.\n' "$label" "$4" >&2
      printf '%s\n' "$out" >&2
      rm -rf "$tmp"
      exit 1
    fi
  }

  local comment_msg='It must be a real YAML line, not a mention of one in a comment.'

  # The two committed negative fixtures. Both leave the plan unguarded; both must be
  # refused, and refused for the anchoring reason rather than by accident.
  run_case 'guard step replaced by a comment' \
    tests/fixtures/contract/aws-plan-guard-commented-out.yml 1 "$comment_msg"
  run_case 'guard step body commented out' \
    tests/fixtures/contract/aws-plan-guard-body-commented-out.yml 1 "$comment_msg"

  # The pin scanner, both directions, derived from the real workflow so they cannot go
  # stale. A real unpinned line is still refused; a commented-out one is not a use of the
  # action and must no longer be reported as one.
  sed 's|^\([[:space:]]*\)uses: \(.*\)/cost-guard@.*$|\1uses: \2/cost-guard@main|' \
    .github/workflows/aws-plan.yml > "$tmp/real-unpinned.yml"
  run_case 'a real unpinned uses: line' "$tmp/real-unpinned.yml" 1 'but the pin in'

  sed 's|^\([[:space:]]*\)- name: Cost guard$|\1# uses: martcoca/cost-guard@main\n\1- name: Cost guard|' \
    .github/workflows/aws-plan.yml > "$tmp/commented-unpinned.yml"
  run_case 'a commented-out unpinned uses:' "$tmp/commented-unpinned.yml" 0 ''

  # The freshness step must not be removable in silence. Derived from the real workflow so
  # it cannot go stale: drop the step and everything indented under it.
  awk '/^      - name: Cost guard freshness$/ { drop = 1; next }
       drop && /^      - name: / { drop = 0 }
       !drop { print }' .github/workflows/aws-plan.yml > "$tmp/no-freshness.yml"
  run_case 'the freshness step deleted' "$tmp/no-freshness.yml" 1 \
    'Missing required contract line'

  # And it must not drift onto a different release from the guard. This is the case the
  # previous scanner could not see at all: it required `@` straight after `cost-guard`, so
  # a sub-action on any ref matched nothing and was reported as conforming.
  sed 's|/cost-guard/freshness@.*$|/cost-guard/freshness@v1.0.1|' \
    .github/workflows/aws-plan.yml > "$tmp/freshness-drifted.yml"
  run_case 'freshness pinned to a different release' "$tmp/freshness-drifted.yml" 1 \
    'but the pin in'

  # And the control: the untouched workflow through the same machinery, so a self-test that
  # passes by refusing everything is not mistaken for one that discriminates.
  run_case 'the real workflow, unmodified' .github/workflows/aws-plan.yml 0 ''

  rm -rf "$tmp"
  printf 'Self-test: the check refuses 5 compromised workflows and accepts 2 sound ones.\n'
}

[[ "$selftest_enabled" -eq 1 ]] && selftest

printf 'CI contract checks passed.\n'
