#!/usr/bin/env bash
# Spec for cmd_status() interrupted iteration detection in bin/ralph. Plain bash, no bats.
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

# --- test dead PID + baseline (should be flagged) ---
test_status_dead_pid_with_baseline() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Create .ralph-logs structure with dead PID and baseline
  local scope="test-milestone"
  mkdir -p ".ralph-logs/$scope"

  # Write a baseline file
  cat > ".ralph-logs/$scope/baseline" <<EOF
sha=abc123def456
issue=42
branch=recovery/test-42
timestamp=$(date +%s)
EOF

  # Write a running file with a definitely dead PID (use 1, which is init and won't respond to user signals)
  # Actually, let's use a negative PID which is definitely invalid
  echo "999999999" > ".ralph-logs/$scope/running"

  # Capture cmd_status output
  local output
  output=$(BACKEND="github" cmd_status 2>&1)

  # Check for interrupted iteration flag
  if echo "$output" | grep -q "INTERRUPTED iterations"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_status: interrupted header not found")
    echo "FAIL: cmd_status: interrupted header not found"
    echo "Output was:"
    echo "$output"
  fi

  # Check for issue number from baseline
  if echo "$output" | grep -q "issue: #42"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_status: issue number not in output")
    echo "FAIL: cmd_status: issue number not in output"
  fi

  # Check for branch from baseline
  if echo "$output" | grep -q "branch: recovery/test-42"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_status: branch not in output")
    echo "FAIL: cmd_status: branch not in output"
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- test alive PID (should be quiet) ---
test_status_alive_pid() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Create .ralph-logs structure with live PID and baseline
  local scope="test-alive"
  mkdir -p ".ralph-logs/$scope"

  # Write a baseline file
  cat > ".ralph-logs/$scope/baseline" <<EOF
sha=abc123def456
issue=99
branch=feature/99
timestamp=$(date +%s)
EOF

  # Write a running file with current PID (definitely alive)
  echo "$$" > ".ralph-logs/$scope/running"

  # Capture cmd_status output
  local output
  output=$(BACKEND="github" cmd_status 2>&1)

  # Check that "INTERRUPTED iterations" header is NOT in output
  if echo "$output" | grep -q "INTERRUPTED iterations"; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_status: interrupted header should not appear for alive PID")
    echo "FAIL: cmd_status: interrupted header should not appear for alive PID"
    echo "Output was:"
    echo "$output"
  else
    PASS=$((PASS+1))
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- test no baseline file (should be quiet) ---
test_status_no_baseline() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Create .ralph-logs structure with running file but NO baseline
  local scope="test-no-baseline"
  mkdir -p ".ralph-logs/$scope"

  # Write only a running file with dead PID
  echo "999999999" > ".ralph-logs/$scope/running"

  # Capture cmd_status output
  local output
  output=$(BACKEND="github" cmd_status 2>&1)

  # Check that "INTERRUPTED iterations" header is NOT in output
  if echo "$output" | grep -q "INTERRUPTED iterations"; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_status: interrupted header should not appear without baseline")
    echo "FAIL: cmd_status: interrupted header should not appear without baseline"
    echo "Output was:"
    echo "$output"
  else
    PASS=$((PASS+1))
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- test no running file (should be quiet) ---
test_status_no_running() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Create .ralph-logs structure with baseline but NO running file
  local scope="test-no-running"
  mkdir -p ".ralph-logs/$scope"

  # Write only a baseline file
  cat > ".ralph-logs/$scope/baseline" <<EOF
sha=abc123def456
issue=88
branch=feature/88
timestamp=$(date +%s)
EOF

  # Capture cmd_status output
  local output
  output=$(BACKEND="github" cmd_status 2>&1)

  # Check that "INTERRUPTED iterations" header is NOT in output
  if echo "$output" | grep -q "INTERRUPTED iterations"; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("cmd_status: interrupted header should not appear without running file")
    echo "FAIL: cmd_status: interrupted header should not appear without running file"
    echo "Output was:"
    echo "$output"
  else
    PASS=$((PASS+1))
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- run tests ---
test_status_dead_pid_with_baseline
test_status_alive_pid
test_status_no_baseline
test_status_no_running

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
