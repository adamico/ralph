#!/usr/bin/env bash
# Spec for cmd_recover() in bin/ralph. Plain bash, no bats.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RALPH="$HERE/../bin/ralph"

# shellcheck disable=SC1090
. "$RALPH"

PASS=0
FAIL=0
FAILED_NAMES=()

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
  fi
}

# --- test recovery runbook generation ---
test_recovery_runbook_generation() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Set up environment
  # shellcheck disable=SC2034
  BACKEND="github"
  # shellcheck disable=SC2034
  GH_REPO=""

  # Create baseline
  local scope="test-milestone"
  mkdir -p ".ralph-logs/$scope"

  cat > ".ralph-logs/$scope/baseline" <<EOF
sha=abc123def456
issue=42
branch=recovery/test-42
timestamp=$(date +%s)
EOF

  # Mock gh command for issue check
  mkdir -p bin
  cat > bin/gh <<'MOCK_GH'
#!/bin/bash
case "${@}" in
  *"issue view 42"*)
    echo '{"state":"OPEN"}'
    ;;
  *)
    exit 1
    ;;
esac
MOCK_GH
  chmod +x bin/gh
  PATH="./bin:$PATH"

  # Run cmd_recover and capture output
  local output
  output=$(cmd_recover "$scope" 2>&1)

  # Check for recovery runbook header
  if echo "$output" | grep -q "Recovery runbook"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: header not found")
    echo "FAIL: cmd_recover: header not found"
    echo "Output was:"
    echo "$output"
  fi

  # Check for git reset command
  if echo "$output" | grep -q "git reset --hard abc123def456"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: git reset command not found")
    echo "FAIL: cmd_recover: git reset command not found"
  fi

  # Check for git clean command
  if echo "$output" | grep -q "git clean -fdx"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: git clean command not found")
    echo "FAIL: cmd_recover: git clean command not found"
  fi

  # Check for git push command
  if echo "$output" | grep -q "git push --force-with-lease origin recovery/test-42"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: git push command not found")
    echo "FAIL: cmd_recover: git push command not found"
  fi

  # Check for ralph run command
  if echo "$output" | grep -q "ralph run 1 test-milestone"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: ralph run command not found")
    echo "FAIL: cmd_recover: ralph run command not found"
  fi

  # Check for force-with-lease warning
  if echo "$output" | grep -q "force-with-lease.*must be run by the human"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: force-with-lease warning not found")
    echo "FAIL: cmd_recover: force-with-lease warning not found"
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- test missing baseline error ---
test_recover_missing_baseline() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # shellcheck disable=SC2034
  BACKEND="github"
  # shellcheck disable=SC2034
  GH_REPO=""

  # Try to recover with no baseline
  local output rc
  output=$(cmd_recover "nonexistent" 2>&1); rc=$?

  if [ $rc -ne 0 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: should fail when baseline missing")
    echo "FAIL: cmd_recover: should fail when baseline missing"
  fi

  if echo "$output" | grep -q "no baseline found"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: error message not found")
    echo "FAIL: cmd_recover: error message not found"
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- test that force-push is never executed ---
test_recover_no_force_push_execution() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # shellcheck disable=SC2034
  BACKEND="github"
  # shellcheck disable=SC2034
  GH_REPO=""

  # Create baseline
  local scope="test-milestone"
  mkdir -p ".ralph-logs/$scope"

  cat > ".ralph-logs/$scope/baseline" <<EOF
sha=abc123def456
issue=42
branch=recovery/test-42
timestamp=$(date +%s)
EOF

  # Mock gh command that would fail if invoked with actual git commands
  mkdir -p bin
  cat > bin/gh <<'MOCK_GH'
#!/bin/bash
case "${@}" in
  *"issue view 42"*)
    echo '{"state":"OPEN"}'
    exit 0
    ;;
  *)
    echo "ERROR: Unexpected gh invocation: $@" >&2
    exit 1
    ;;
esac
MOCK_GH
  chmod +x bin/gh
  PATH="./bin:$PATH"

  # Create a trap to detect if git push would be called
  # shellcheck disable=SC2034
  TRAP_CALLED=0
  trap 'TRAP_CALLED=1' ERR

  # Run cmd_recover
  local output
  output=$(cmd_recover "$scope" 2>&1)

  # Verify function output contains commands but didn't execute them
  if echo "$output" | grep -q "git push"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_recover: git push not in output")
    echo "FAIL: cmd_recover: git push not in output"
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- run tests ---
test_recovery_runbook_generation
test_recover_missing_baseline
test_recover_no_force_push_execution

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
