#!/usr/bin/env bash
# Spec for read_active_marker() in bin/ralph.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RALPH="$HERE/../bin/ralph"

# shellcheck disable=SC1090
. "$RALPH"

PASS=0
FAIL=0
FAILED_NAMES=()

assert_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$label")
    echo "FAIL: $label (expected rc $expected, got $actual)"
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  expected to contain: '$needle'"
    echo "  actual:              '$haystack'"
  fi
}

ws=$(mktemp -d)
cleanup() { rm -rf "$ws"; }

# Override MARKER_FILE to point to our temp dir
MARKER_FILE="$ws/ACTIVE"

# --- case 1: missing/empty file -> rc 10 ---
rm -f "$MARKER_FILE"
out=$(read_active_marker 2>&1); rc=$?
assert_rc "missing-file/rc" 10 "$rc"
cleanup() { :; }

# --- case 2: valid single-word dirname -> echoes it ---
echo "my-feature" > "$MARKER_FILE"
out=$(read_active_marker 2>&1); rc=$?
assert_rc "valid/rc" 0 "$rc"
assert_eq "valid/output" "my-feature" "$out"

# --- case 3: agent clobbering bug — first line has spaces (summary written to ACTIVE) ---
printf 'my-feature — iteration summary: done\nmore lines\n' > "$MARKER_FILE"
out=$(read_active_marker 2>&1); rc=$?
assert_rc "multiline/rc" 1 "$rc"
assert_contains "multiline/msg" "malformed" "$out"

# --- case 4: first line has slash -> malformed ---
echo "foo/bar" > "$MARKER_FILE"
out=$(read_active_marker 2>&1); rc=$?
assert_rc "slash/rc" 1 "$rc"
assert_contains "slash/msg" "malformed" "$out"

# --- case 5: first line has spaces -> malformed ---
echo "foo bar" > "$MARKER_FILE"
out=$(read_active_marker 2>&1); rc=$?
assert_rc "spaces/rc" 1 "$rc"
assert_contains "spaces/msg" "malformed" "$out"

# --- case 6: trailing newline (normal write) -> still valid ---
printf 'my-feature\n' > "$MARKER_FILE"
out=$(read_active_marker 2>&1); rc=$?
assert_rc "trailing-newline/rc" 0 "$rc"
assert_eq "trailing-newline/output" "my-feature" "$out"

rm -rf "$ws"

# --- summary ---
echo
echo "active_marker_spec: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
