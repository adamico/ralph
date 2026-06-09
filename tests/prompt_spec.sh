#!/usr/bin/env bash
# Spec for agent prompt failure semantics. Plain bash, no bats.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RALPH="$HERE/../bin/ralph"

# shellcheck disable=SC1090
. "$RALPH"

PASS=0
FAIL=0
FAILED_NAMES=()

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  missing: $needle"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  unexpected: $needle"
  else
    PASS=$((PASS+1))
  fi
}

# The agent must distinguish tests from lint. Red tests after a push are the
# primary repair loop and must be fixed in the current iteration. Lint failures
# should be fixed when focused/small, but broad lint debt gets spun out into a
# separate issue for HITL or another ralph session instead of being swallowed by
# the current loop.
gh_prompt=$(build_prompt_gh "test-milestone" "60")
assert_contains "gh prompt retries red post-push tests" "If tests are red after a push, diagnose and repair the failing tests in this iteration" "$gh_prompt"
assert_contains "gh prompt separates lint from tests" "Treat lint separately from tests" "$gh_prompt"
assert_contains "gh prompt allows lint issue split" "If lint repair is broad, risky, or outside this issue's scope, create a separate lint remediation issue" "$gh_prompt"
assert_contains "gh prompt mentions hitl for lint split" "HITL or another ralph session" "$gh_prompt"
assert_not_contains "gh prompt does not equate gate red with blocked" "On failure (gate red after push" "$gh_prompt"

fs_prompt=$(build_prompt ".scratch/test" ".scratch/test/issues")
assert_contains "fs prompt retries red post-push tests" "If tests are red after a push, diagnose and repair the failing tests in this iteration" "$fs_prompt"
assert_contains "fs prompt separates lint from tests" "Treat lint separately from tests" "$fs_prompt"
assert_contains "fs prompt allows lint issue split" "If lint repair is broad, risky, or outside this issue's scope, create a separate lint remediation issue" "$fs_prompt"
assert_contains "fs prompt mentions hitl for lint split" "HITL or another ralph session" "$fs_prompt"
assert_not_contains "fs prompt does not equate gate red with blocked" "On failure (gate red after push" "$fs_prompt"

TOTAL=$((PASS+FAIL))
echo "prompt_spec: $PASS/$TOTAL assertions passed"
if [ "$FAIL" -ne 0 ]; then
  printf 'Failed assertions:\n'
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
