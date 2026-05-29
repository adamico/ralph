#!/usr/bin/env bash
# Spec for record_baseline() and read_baseline() in bin/ralph. Plain bash, no bats.
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

# --- test record_baseline and read_baseline round-trip ---
test_baseline_roundtrip() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Initialize a git repo for record_baseline to work
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create a dummy commit
  touch dummy.txt
  git add dummy.txt
  git commit -q -m "initial"

  # Get the actual SHA and branch for verification
  local expected_sha expected_branch expected_issue expected_ts_approx
  expected_sha=$(git rev-parse HEAD)
  expected_branch=$(git branch --show-current)
  expected_issue="test-issue-123"
  expected_ts_approx=$(date +%s)

  # Record baseline
  local scope="test-scope"
  mkdir -p ".ralph-logs/$scope"
  record_baseline "$scope" "$expected_issue"

  # Verify file exists
  if [ ! -f ".ralph-logs/$scope/baseline" ]; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("baseline: file not created")
    echo "FAIL: baseline: file not created"
  else
    PASS=$((PASS+1))
  fi

  # Read baseline back
  if read_baseline "$scope"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("baseline: read_baseline failed")
    echo "FAIL: baseline: read_baseline failed"
  fi

  # Verify SHA
  assert_eq "baseline: SHA roundtrips" "$expected_sha" "$BASELINE_SHA"

  # Verify issue
  assert_eq "baseline: issue roundtrips" "$expected_issue" "$BASELINE_ISSUE"

  # Verify branch
  assert_eq "baseline: branch roundtrips" "$expected_branch" "$BASELINE_BRANCH"

  # Verify timestamp is recent (within 2 seconds of now)
  local ts_now expected_ts_lower expected_ts_upper
  ts_now=$(date +%s)
  expected_ts_lower=$((expected_ts_approx - 1))
  expected_ts_upper=$((ts_now + 1))
  if [ "$BASELINE_TIMESTAMP" -ge "$expected_ts_lower" ] && [ "$BASELINE_TIMESTAMP" -le "$expected_ts_upper" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("baseline: timestamp out of range")
    echo "FAIL: baseline: timestamp out of range"
    echo "  expected range: $expected_ts_lower-$expected_ts_upper"
    echo "  actual: $BASELINE_TIMESTAMP"
  fi

  # Cleanup
  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- test read_baseline with missing file ---
test_baseline_missing_file() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Try to read from a scope that doesn't exist
  if read_baseline "nonexistent-scope"; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("baseline: read_baseline should fail on missing file")
    echo "FAIL: baseline: read_baseline should fail on missing file"
  else
    PASS=$((PASS+1))
  fi

  # Cleanup
  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- test baseline overwrite ---
test_baseline_overwrite() {
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # Initialize git repo
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  touch file1.txt
  git add file1.txt
  git commit -q -m "first"

  local scope="test-scope"
  mkdir -p ".ralph-logs/$scope"

  # Record first baseline
  record_baseline "$scope" "issue-1"
  local first_ts
  first_ts=$BASELINE_TIMESTAMP 2>/dev/null || true

  # Sleep a bit to ensure timestamp difference
  sleep 0.1

  # Create another commit
  touch file2.txt
  git add file2.txt
  git commit -q -m "second"

  # Record second baseline with different issue
  record_baseline "$scope" "issue-2"

  # Read back and verify it contains the second issue
  read_baseline "$scope"
  assert_eq "baseline: overwrite keeps latest issue" "issue-2" "$BASELINE_ISSUE"

  # Cleanup
  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- run tests ---
test_baseline_roundtrip
test_baseline_missing_file
test_baseline_overwrite

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
