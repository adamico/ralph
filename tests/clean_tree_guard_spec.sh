#!/usr/bin/env bash
# Spec for check_clean_tree_guard() in bin/ralph (ADR-0009 false-green guard).
# Plain bash, no bats. Each case runs in its own throwaway git repo with a
# fake "origin" so divergence can be exercised offline.
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

# Build a repo with a bare origin and one pushed commit on branch `work`.
new_repo() {
  ws=$(mktemp -d); cd "$ws" || exit 1
  git init -q origin.git --bare
  git init -q repo
  cd repo || exit 1
  git config user.email t@t; git config user.name t
  git remote add origin "$ws/origin.git"
  git checkout -q -b work
  echo a > a.txt; git add a.txt; git commit -qm init
  git push -q -u origin work
}

cleanup() { cd /; rm -rf "$ws"; }

# --- case 1: clean tree, in sync -> pass ---
new_repo
out=$(check_clean_tree_guard 2>&1); rc=$?
assert_rc "clean/in-sync-rc" 0 "$rc"
cleanup

# --- case 2: dirty tree (untracked) -> refuse ---
new_repo
echo x > untracked.txt
out=$(check_clean_tree_guard 2>&1); rc=$?
assert_rc       "dirty/rc"  1 "$rc"
assert_contains "dirty/msg" "working tree is dirty" "$out"
cleanup

# --- case 3: dirty tree (modified) -> refuse ---
new_repo
echo b >> a.txt
out=$(check_clean_tree_guard 2>&1); rc=$?
assert_rc "dirty-modified/rc" 1 "$rc"
cleanup

# --- case 4: unpushed commit (HEAD != origin/work) -> refuse ---
new_repo
echo c > c.txt; git add c.txt; git commit -qm wip
out=$(check_clean_tree_guard 2>&1); rc=$?
assert_rc       "unpushed/rc"  1 "$rc"
assert_contains "unpushed/msg" "differs from origin/work" "$out"
cleanup

# --- case 5: RALPH_ALLOW_DIRTY=1 overrides ---
new_repo
echo x > untracked.txt
out=$(RALPH_ALLOW_DIRTY=1 check_clean_tree_guard 2>&1); rc=$?
assert_rc "override/rc" 0 "$rc"
cleanup

# --- case 6: no upstream ref -> divergence check skipped (clean still passes) ---
new_repo
git checkout -q -b orphan
out=$(check_clean_tree_guard 2>&1); rc=$?
assert_rc "no-upstream/rc" 0 "$rc"
cleanup

# --- case 7: not a git repo -> guard is a no-op ---
ws=$(mktemp -d); cd "$ws" || exit 1
out=$(check_clean_tree_guard 2>&1); rc=$?
assert_rc "non-repo/rc" 0 "$rc"
cleanup

# --- summary ---
echo
echo "clean_tree_guard_spec: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
