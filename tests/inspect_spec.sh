#!/usr/bin/env bash
# Spec for cmd_inspect() and friends in bin/ralph (list / replay / tail-guard
# + fs milestone inference). Plain bash, no bats. Consolidates the throwaway
# root-level test_*.sh scratch scripts into the repo test convention.
#
# Not covered (needs network / would block): github milestone inference
# (infer_milestone_gh calls gh) and the live tail loop (blocks while the
# running file exists). Those paths are exercised by passing an explicit
# scope / testing the tail guards only.
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
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  expected to contain: '$needle'"
    echo "  actual:              '$haystack'"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  expected NOT to contain: '$needle'"
  fi
}

assert_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label (expected rc $expected, got $actual)"
  fi
}

# Each case runs in its own temp workspace so the relative .ralph-logs /
# .scratch paths are isolated.
new_ws() { ws=$(mktemp -d); cd "$ws" || exit 1; }

write_iter() {
  # write_iter <logs_dir> <iter#> <ts> <promise|""> <issue#|"">
  local dir="$1" n="$2" ts="$3" promise="$4" issue="$5"
  mkdir -p "$dir"
  local f="$dir/iter-$n-$ts.jsonl"
  if [ -n "$issue" ]; then
    printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Picked issue: #$issue\"}]}}" > "$f"
  else
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}' > "$f"
  fi
  if [ -n "$promise" ]; then
    printf '%s\n' "{\"type\":\"result\",\"result\":\"<promise>$promise</promise>\"}" >> "$f"
  fi
}

# --- case 1: list, no logs dir ---
new_ws
out=$(BACKEND=github cmd_inspect_list missing 2>&1)
assert_contains "list/no-logs-dir" "no logs found for scope 'missing'" "$out"
cd /; rm -rf "$ws"

# --- case 2: list, dir exists but empty ---
new_ws
mkdir -p .ralph-logs/empty
out=$(BACKEND=github cmd_inspect_list empty 2>&1)
assert_contains "list/empty" "(no iterations logged)" "$out"
cd /; rm -rf "$ws"

# --- case 3: list, with iterations (promise + issue extracted) ---
new_ws
write_iter .ralph-logs/m 1 1609459200 COMPLETE 42
out=$(BACKEND=github cmd_inspect_list m 2>&1)
assert_contains "list/promise" "COMPLETE" "$out"
assert_contains "list/issue"   "42"       "$out"
cd /; rm -rf "$ws"

# --- case 4: replay, valid iteration ---
new_ws
write_iter .ralph-logs/m 1 1609459200 COMPLETE 42
out=$(BACKEND=github cmd_inspect_replay m 1 2>&1); rc=$?
assert_rc       "replay/valid-rc"      0 "$rc"
assert_contains "replay/header"        "=== Iteration 1 (Issue #42) ===" "$out"
assert_contains "replay/promise"       "Promise: COMPLETE" "$out"
cd /; rm -rf "$ws"

# --- case 5: replay, missing iteration ---
new_ws
mkdir -p .ralph-logs/m
out=$(BACKEND=github cmd_inspect_replay m 9 2>&1); rc=$?
assert_rc       "replay/missing-rc"   1 "$rc"
assert_contains "replay/missing-msg"  "iteration 9 not found" "$out"
cd /; rm -rf "$ws"

# --- case 6: replay, non-numeric iter rejected via cmd_inspect ---
new_ws
write_iter .ralph-logs/m 1 1609459200 COMPLETE 42
out=$(BACKEND=github cmd_inspect m abc 2>&1); rc=$?
assert_rc       "replay/non-numeric-rc"  1 "$rc"
assert_contains "replay/non-numeric-msg" "must be a non-negative integer" "$out"
cd /; rm -rf "$ws"

# --- case 7: fs backend infers scope from the active marker ---
new_ws
mkdir -p .scratch
echo "my-prd" > .scratch/ACTIVE
write_iter .ralph-logs/my-prd 1 1609459200 COMPLETE 7
out=$(BACKEND=fs MARKER_FILE=".scratch/ACTIVE" cmd_inspect 2>&1); rc=$?
assert_rc       "fs/infer-rc"     0 "$rc"
assert_contains "fs/infer-scope"  "Iterations in my-prd" "$out"
cd /; rm -rf "$ws"

# --- case 8: fs backend, no marker -> error ---
new_ws
out=$(BACKEND=fs MARKER_FILE=".scratch/ACTIVE" cmd_inspect 2>&1); rc=$?
assert_rc       "fs/no-marker-rc"  1 "$rc"
assert_contains "fs/no-marker-msg" "no active PRD" "$out"
cd /; rm -rf "$ws"

# --- case 9: tail guard, no logs dir ---
new_ws
out=$(BACKEND=github cmd_inspect_tail nope 2>&1); rc=$?
assert_rc       "tail/no-logs-rc"  1 "$rc"
assert_contains "tail/no-logs-msg" "no logs found for scope 'nope'" "$out"
cd /; rm -rf "$ws"

# --- case 10: tail guard, logs dir but no running session ---
new_ws
mkdir -p .ralph-logs/m
out=$(BACKEND=github cmd_inspect_tail m 2>&1); rc=$?
assert_rc       "tail/no-running-rc"  1 "$rc"
assert_contains "tail/no-running-msg" "no running session in scope 'm'" "$out"
cd /; rm -rf "$ws"

# --- case 11: tail ignores non-jsonl files (issue #59 regression) ---
new_ws
write_iter .ralph-logs/m 1 1609459200 COMPLETE 42
echo "invalid json" > .ralph-logs/m/iter-1-1609459200.final.txt
touch .ralph-logs/m/running
# run tail in background, give it a moment to loop, then kill it
(BACKEND=github cmd_inspect_tail m > out.log 2>&1 & pid=$!; sleep 0.5; kill $pid 2>/dev/null)
out=$(cat out.log)
assert_contains     "tail/bug59-starts" "tailing live session" "$out"
assert_not_contains "tail/bug59-nojq"   "jq: parse error" "$out"
assert_not_contains "tail/bug59-nobash" "integer expression expected" "$out"
cd /; rm -rf "$ws"

# --- summary ---
echo
echo "inspect_spec: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
