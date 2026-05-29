#!/usr/bin/env bash
# Spec for recovery_plan() in bin/ralph. Plain bash, no bats.
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

# --- test recovery_plan output format ---
test_recovery_plan_format() {
  local sha="abc123def456" milestone="test-milestone" issue="42" branch="recovery/test"

  local output
  output=$(recovery_plan "$sha" "$milestone" "$issue" "$branch")

  # Test that output contains all expected commands
  if echo "$output" | grep -q "git reset --hard $sha"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: git reset command not found")
    echo "FAIL: recovery_plan: git reset command not found"
    echo "Output was:"
    echo "$output"
  fi

  if echo "$output" | grep -q "git clean -fdx"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: git clean command not found")
    echo "FAIL: recovery_plan: git clean command not found"
  fi

  if echo "$output" | grep -q "git push --force-with-lease origin $branch"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: git push command not found")
    echo "FAIL: recovery_plan: git push command not found"
  fi

  if echo "$output" | grep -q "ralph run 1 $milestone"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: ralph run command not found")
    echo "FAIL: recovery_plan: ralph run command not found"
  fi
}

# --- test that recovery_plan uses branch verbatim ---
test_recovery_plan_branch_verbatim() {
  local sha="deadbeef" milestone="prod" issue="99" branch="feature/my-feature"

  local output
  output=$(recovery_plan "$sha" "$milestone" "$issue" "$branch")

  # Verify the exact branch is in the output, not 'main' or anything else
  if echo "$output" | grep -q "git push --force-with-lease origin feature/my-feature"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: branch not used verbatim")
    echo "FAIL: recovery_plan: branch not used verbatim"
    echo "Output was:"
    echo "$output"
  fi

  # Make sure 'main' doesn't appear in the output
  if echo "$output" | grep -q "origin main"; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: 'main' incorrectly appeared in output")
    echo "FAIL: recovery_plan: 'main' incorrectly appeared in output"
  else
    PASS=$((PASS+1))
  fi
}

# --- test ordered command list ---
test_recovery_plan_order() {
  local sha="abc123" milestone="m1" issue="1" branch="b1"

  local output
  output=$(recovery_plan "$sha" "$milestone" "$issue" "$branch")

  # Convert to array of lines
  local lines=()
  while IFS= read -r line; do
    [ -n "$line" ] && lines+=("$line")
  done <<< "$output"

  # Verify order: git reset, git clean, git push, ralph run
  if [ ${#lines[@]} -ge 4 ]; then
    assert_eq "recovery_plan: line 1 is git reset" "git reset --hard $sha" "${lines[0]}"
    assert_eq "recovery_plan: line 2 is git clean" "git clean -fdx" "${lines[1]}"
    assert_eq "recovery_plan: line 3 is git push" "git push --force-with-lease origin $branch" "${lines[2]}"
    assert_eq "recovery_plan: line 4 is ralph run" "ralph run 1 $milestone" "${lines[3]}"
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: fewer than 4 output lines")
    echo "FAIL: recovery_plan: fewer than 4 output lines (got ${#lines[@]})"
  fi
}

# --- test pure function (no side effects) ---
test_recovery_plan_pure() {
  # This test verifies the function doesn't access filesystem or network
  # by checking it produces output without needing git or any other tools

  local sha="test123" milestone="test-m" issue="test-i" branch="test-b"

  # Function should complete successfully even in a directory with no git repo
  local test_dir
  test_dir=$(mktemp -d)
  local orig_pwd="$PWD"
  cd "$test_dir" || exit 1

  # source RALPH again in this directory
  # shellcheck disable=SC1090
  . "$RALPH"

  local output
  output=$(recovery_plan "$sha" "$milestone" "$issue" "$branch" 2>&1)

  if [ -z "$output" ]; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: no output in non-git directory")
    echo "FAIL: recovery_plan: no output in non-git directory"
  else
    PASS=$((PASS+1))
  fi

  # Verify no git errors in output
  if echo "$output" | grep -q "fatal\|error"; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("recovery_plan: git error detected")
    echo "FAIL: recovery_plan: git error detected"
    echo "$output"
  else
    PASS=$((PASS+1))
  fi

  cd "$orig_pwd" || exit 1
  rm -rf "$test_dir"
}

# --- run tests ---
test_recovery_plan_format
test_recovery_plan_branch_verbatim
test_recovery_plan_order
test_recovery_plan_pure

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
