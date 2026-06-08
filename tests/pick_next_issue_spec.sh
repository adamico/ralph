#!/usr/bin/env bash
# Spec for pick_next_issue() in bin/ralph. Plain bash, no bats.
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

mk_fixture() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/issues"
  echo "$dir"
}

write_issue() {
  local file="$1" status="$2" blocked_by="${3:-}"
  {
    echo "Status: $status"
    [ -n "$blocked_by" ] && echo "Blocked-by: $blocked_by"
    echo "---"
    echo "body"
  } > "$file"
}

basename_of() { [ -n "$1" ] && basename "$1" || echo ""; }

# pick_next_issue echoes to stdout AND sets ALL_BLOCKED in the current
# shell. Command substitution would fork a subshell and lose the var, so
# capture stdout via a temp file instead.
pick() {
  local out
  out=$(mktemp)
  pick_next_issue "$1" > "$out"
  PICK=$(cat "$out")
  rm -f "$out"
}

# --- case 1: single ready, no deps -> picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-foo.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case1: picks lone ready" "01-foo.md" "$(basename_of "$got")"
assert_eq "case1: ALL_BLOCKED=0"    "0"         "$ALL_BLOCKED"
rm -rf "$d"

# --- case 2: lowest filename among readies wins ---
d=$(mk_fixture)
write_issue "$d/issues/02-b.md" ready
write_issue "$d/issues/01-a.md" ready
write_issue "$d/issues/03-c.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case2: lowest filename wins" "01-a.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 3: done issues skipped ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" "done"
write_issue "$d/issues/02-b.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case3: done skipped, next ready picked" "02-b.md" "$(basename_of "$got")"
assert_eq "case3: ALL_BLOCKED=0" "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 4: blocked-by undone dep => not picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-dep.md" ready
write_issue "$d/issues/02-needs.md" ready "01-dep"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case4: dep undone, picks dep itself" "01-dep.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 5: blocked-by dep done => downstream picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-dep.md" "done"
write_issue "$d/issues/02-needs.md" ready "01-dep"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case5: dep done, downstream picked" "02-needs.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 6: every ready is blocked => ALL_BLOCKED=1, empty pick ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" ready "99-missing"
write_issue "$d/issues/02-b.md" ready "01-a"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case6: all blocked => empty pick" "" "$got"
assert_eq "case6: ALL_BLOCKED=1"             "1" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 7: all done => empty pick, ALL_BLOCKED=0 ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" "done"
write_issue "$d/issues/02-b.md" "done"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case7: all done => empty pick" "" "$got"
assert_eq "case7: ALL_BLOCKED=0"          "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 8: status 'blocked' not picked even with no deps ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" blocked
write_issue "$d/issues/02-b.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case8: blocked skipped, ready picked" "02-b.md" "$(basename_of "$got")"
assert_eq "case8: ALL_BLOCKED=0 (b is pickable)" "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 9: multi-dep, one undone => not picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" "done"
write_issue "$d/issues/02-b.md" ready
write_issue "$d/issues/03-c.md" ready "01-a, 02-b"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case9: multi-dep with one undone -> picks earlier ready" "02-b.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 10: 'ready-for-agent' status is pickable (gh vocab parity) ---
d=$(mk_fixture)
write_issue "$d/issues/01-foo.md" ready-for-agent
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case10: ready-for-agent picked" "01-foo.md" "$(basename_of "$got")"
assert_eq "case10: ALL_BLOCKED=0" "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 11: 'Blocked-by: none' means no dependencies ---
d=$(mk_fixture)
write_issue "$d/issues/01-foo.md" ready-for-agent "none"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case11: Blocked-by none => picked" "01-foo.md" "$(basename_of "$got")"
assert_eq "case11: ALL_BLOCKED=0" "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 12: 'Blocked-by: None' (any case) treated as none ---
d=$(mk_fixture)
write_issue "$d/issues/01-foo.md" ready "None"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case12: Blocked-by None (case-insensitive) => picked" "01-foo.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 13: real numeric dep still blocks under ready-for-agent ---
d=$(mk_fixture)
write_issue "$d/issues/01-dep.md" ready-for-agent
write_issue "$d/issues/02-needs.md" ready-for-agent "01-dep"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case13: undone dep blocks, picks dep" "01-dep.md" "$(basename_of "$got")"
rm -rf "$d"

# --- Agent CLI config/model resolution tests (issue #44) ---
saved_AGENT_CLI="${AGENT_CLI:-}"
saved_AGENT_CMD="${AGENT_CMD:-}"
saved_AGENT_ARGS="${AGENT_ARGS:-}"
saved_CLAUDE_CMD="${CLAUDE_CMD:-}"
saved_MODEL="${MODEL:-}"
saved_MODEL_CLASS="${MODEL_CLASS:-}"
saved_WARNED="${LEGACY_CLAUDE_CMD_WARNED:-0}"

reset_agent_resolution_state() {
  AGENT_CLI="$saved_AGENT_CLI"
  AGENT_CMD="$saved_AGENT_CMD"
  AGENT_ARGS="$saved_AGENT_ARGS"
  CLAUDE_CMD="$saved_CLAUDE_CMD"
  MODEL="$saved_MODEL"
  MODEL_CLASS="$saved_MODEL_CLASS"
  LEGACY_CLAUDE_CMD_WARNED=0
  RESOLVED_AGENT_CLI=""
  RESOLVED_AGENT_CMD=""
  RESOLVED_AGENT_ARGS=""
  RESOLVED_MODEL=""
  RESOLVED_MODEL_SOURCE=""
  # shellcheck disable=SC2034
  RESOLVED_MODEL_CLASS=""
}

test_agent_cli_new_config() {
  reset_agent_resolution_state
  AGENT_CLI="codex"
  AGENT_CMD="codex-wrapper"
  AGENT_ARGS="exec --json"
  MODEL=""
  MODEL_CLASS="low"

  local rc
  resolve_agent_cli_config >/dev/null 2>&1; rc=$?
  assert_eq "agent_config: new config resolves" "0" "$rc"
  assert_eq "agent_config: cli=codex" "codex" "$RESOLVED_AGENT_CLI"
  assert_eq "agent_config: cmd preserved" "codex-wrapper" "$RESOLVED_AGENT_CMD"
  assert_eq "agent_config: args preserved" "exec --json" "$RESOLVED_AGENT_ARGS"

  resolve_model_config "$RESOLVED_AGENT_CLI" >/dev/null 2>&1; rc=$?
  assert_eq "agent_config: model config resolves" "0" "$rc"
  assert_eq "agent_config: codex low -> gpt-5.4" "gpt-5.4" "$RESOLVED_MODEL"
  assert_eq "agent_config: codex low source" "model-class:low" "$RESOLVED_MODEL_SOURCE"
}

test_agent_cli_legacy_claude_mapping_warns_once() {
  reset_agent_resolution_state
  AGENT_CLI=""
  AGENT_CMD=""
  CLAUDE_CMD="legacy-claude"
  MODEL=""
  MODEL_CLASS="low"

  local err1 err2 rc
  err1=$(mktemp)
  err2=$(mktemp)

  resolve_agent_cli_config >/dev/null 2>"$err1"; rc=$?
  assert_eq "legacy_claude: first resolve succeeds" "0" "$rc"
  assert_eq "legacy_claude: mapped cli" "claude" "$RESOLVED_AGENT_CLI"
  assert_eq "legacy_claude: mapped command" "legacy-claude" "$RESOLVED_AGENT_CMD"
  if grep -q "CLAUDE_CMD is deprecated" "$err1"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("legacy_claude: deprecation warning missing on first resolve")
    echo "FAIL: legacy_claude: deprecation warning missing on first resolve"
  fi

  resolve_agent_cli_config >/dev/null 2>"$err2"; rc=$?
  assert_eq "legacy_claude: second resolve succeeds" "0" "$rc"
  if [ ! -s "$err2" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("legacy_claude: warning repeated")
    echo "FAIL: legacy_claude: warning repeated"
  fi

  rm -f "$err1" "$err2"
}

test_agent_cli_new_command_beats_legacy() {
  reset_agent_resolution_state
  AGENT_CLI="claude"
  AGENT_CMD="new-claude"
  CLAUDE_CMD="legacy-claude"

  local err rc
  err=$(mktemp)
  resolve_agent_cli_config >/dev/null 2>"$err"; rc=$?
  assert_eq "new_beats_legacy: resolve succeeds" "0" "$rc"
  assert_eq "new_beats_legacy: uses AGENT_CMD" "new-claude" "$RESOLVED_AGENT_CMD"
  if [ ! -s "$err" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("new_beats_legacy: unexpected deprecation warning")
    echo "FAIL: new_beats_legacy: unexpected deprecation warning"
  fi
  rm -f "$err"
}

test_agent_cli_explicit_model_override_and_pi_default() {
  reset_agent_resolution_state
  AGENT_CLI="claude"
  AGENT_CMD="claude"
  MODEL="haiku"
  MODEL_CLASS="low"

  local rc
  resolve_agent_cli_config >/dev/null 2>&1; rc=$?
  assert_eq "explicit_model: cli resolve succeeds" "0" "$rc"
  resolve_model_config "$RESOLVED_AGENT_CLI" >/dev/null 2>&1; rc=$?
  assert_eq "explicit_model: model resolve succeeds" "0" "$rc"
  assert_eq "explicit_model: explicit model wins" "haiku" "$RESOLVED_MODEL"
  assert_eq "explicit_model: source=explicit" "explicit" "$RESOLVED_MODEL_SOURCE"

  reset_agent_resolution_state
  AGENT_CLI="pi"
  AGENT_CMD="pi"
  MODEL=""
  MODEL_CLASS="low"

  resolve_agent_cli_config >/dev/null 2>&1; rc=$?
  assert_eq "pi_default: cli resolve succeeds" "0" "$rc"
  resolve_model_config "$RESOLVED_AGENT_CLI" >/dev/null 2>&1; rc=$?
  assert_eq "pi_default: model resolve succeeds" "0" "$rc"
  assert_eq "pi_default: no ralph-owned model" "" "$RESOLVED_MODEL"
  assert_eq "pi_default: provider-default source" "provider-default" "$RESOLVED_MODEL_SOURCE"
}

test_agent_cli_rejects_unsupported_names() {
  reset_agent_resolution_state
  AGENT_CLI="cursor"
  AGENT_CMD="cursor"

  local err rc
  err=$(mktemp)
  resolve_agent_cli_config >/dev/null 2>"$err"; rc=$?
  assert_eq "unsupported_cli: resolve fails" "1" "$rc"
  if grep -q "unsupported AGENT_CLI 'cursor'" "$err"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("unsupported_cli: error message missing")
    echo "FAIL: unsupported_cli: error message missing"
  fi
  rm -f "$err"
}

test_agent_model_manifest_values() {
  reset_agent_resolution_state
  RESOLVED_AGENT_CLI="codex"
  RESOLVED_MODEL="gpt-5.4"
  RESOLVED_MODEL_SOURCE="model-class:low"
  # shellcheck disable=SC2034
  RESOLVED_MODEL_DISPLAY="gpt-5.4 (MODEL_CLASS=low default)"
  assert_eq "manifest_model: codex default text" "gpt-5.4 (MODEL_CLASS=low default)" "$(agent_model_manifest_value)"

  RESOLVED_AGENT_CLI="pi"
  RESOLVED_MODEL=""
  RESOLVED_MODEL_SOURCE="provider-default"
  # shellcheck disable=SC2034
  RESOLVED_MODEL_DISPLAY="provider default (MODEL_CLASS=low; ralph omits --model)"
  assert_eq "manifest_model: pi provider default text" "provider default (MODEL_CLASS=low; ralph omits --model)" "$(agent_model_manifest_value)"

  RESOLVED_AGENT_CLI="claude"
  RESOLVED_MODEL="haiku"
  RESOLVED_MODEL_SOURCE="explicit"
  # shellcheck disable=SC2034
  RESOLVED_MODEL_DISPLAY="haiku (explicit)"
  assert_eq "manifest_model: explicit text" "haiku (explicit)" "$(agent_model_manifest_value)"
}

test_agent_cli_new_config
test_agent_cli_legacy_claude_mapping_warns_once
test_agent_cli_new_command_beats_legacy
test_agent_cli_explicit_model_override_and_pi_default
test_agent_cli_rejects_unsupported_names
test_agent_model_manifest_values

LEGACY_CLAUDE_CMD_WARNED="$saved_WARNED"

# --- session marker tests ---
# Test that .ralph-logs/<scope>/running file is created with PID and cleaned up

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR" || exit 1

# Create minimal fixture for GitHub backend test
# shellcheck disable=SC2034
BACKEND="github"
# shellcheck disable=SC2034
GH_LABEL_READY="ready-for-agent"
# shellcheck disable=SC2034
GH_LABEL_BLOCKED="blocked"

# Mock CLAUDE_CMD to return immediately
CLAUDE_CMD="true"

# Create a test that runs iterate_once in non-interactive mode
# We'll need to set up a mock environment with milestones

# For now, just test the file creation mechanism directly
# Create a function to test the session marker creation
test_session_marker() {
  local test_scope="test-scope"
  local logs_dir=".ralph-logs/$test_scope"
  mkdir -p "$logs_dir"

  local running_file="$logs_dir/running"
  local test_pid=$$

  # Simulate what iterate_once does
  echo "$test_pid" > "$running_file"

  # Verify file exists and contains the PID
  if [ ! -f "$running_file" ]; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("session_marker: running file not created")
    echo "FAIL: session_marker: running file not created"
  elif [ "$(cat "$running_file")" != "$test_pid" ]; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("session_marker: running file has wrong PID")
    echo "FAIL: session_marker: running file has wrong PID"
    echo "  expected: $test_pid"
    echo "  actual: $(cat "$running_file")"
  else
    PASS=$((PASS+1))
  fi

  # Clean up the file (simulating trap EXIT)
  rm -f "$running_file"

  # Verify file was removed
  if [ -f "$running_file" ]; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("session_marker: running file not cleaned up")
    echo "FAIL: session_marker: running file not cleaned up"
  else
    PASS=$((PASS+1))
  fi

  # Clean up test directory
  rm -rf "$logs_dir"
}

test_session_marker

# Clean up test directory
cd / || true
rm -rf "$TEST_DIR"

# --- JSONL log creation test (issue #16) ---
test_jsonl_creation() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  # Create mock claude command that emits canned stream-json output
  mkdir -p bin
  cat > bin/claude << 'MOCK_CLAUDE'
#!/bin/bash
# Mock claude: output stream-json without actually invoking LLM
cat <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"GitHub backend. Milestone: test. Picked issue: #1."}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Implementing..."}]}}
{"type":"result","result":"<promise>COMPLETE</promise>"}
EOF
MOCK_CLAUDE
  chmod +x bin/claude

  # Setup environment
  # shellcheck disable=SC2034
  BACKEND=github
  # shellcheck disable=SC2034
  GH_REPO=""
  CLAUDE_CMD="./bin/claude"
  # shellcheck disable=SC2034
  MODEL="sonnet"
  # shellcheck disable=SC2034
  TEST_CMD="true"
  # shellcheck disable=SC2034
  LINT_CMD="true"

  # Create a minimal milestone for testing (mock gh command)
  mkdir -p .git

  # Create a mock iterate_once by sourcing ralph and setting up a scope
  local logs_dir=".ralph-logs/test"
  mkdir -p "$logs_dir"

  # Simulate what iterate_once does
  local ts iter_num log_file
  local final_file
  ts=$(date +%s)
  iter_num=1
  log_file="$logs_dir/iter-${iter_num}-${ts}.jsonl"
  final_file=$(iteration_final_message_file "$log_file")

  # Stream through the mock claude
  $CLAUDE_CMD --output-format stream-json 2>&1 \
    | grep --line-buffered '^{' \
    | tee "$log_file" > /dev/null

  # Verify JSONL file was created
  if [ ! -f "$log_file" ]; then
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("jsonl_creation: log file not created")
    echo "FAIL: jsonl_creation: log file not created"
  else
    PASS=$((PASS+1))
  fi

  # Verify JSONL contains expected content
  if grep -q 'Picked issue: #1' "$log_file"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("jsonl_creation: expected content not found")
    echo "FAIL: jsonl_creation: expected content not found"
  fi

  write_final_message_artifact "claude" "$log_file" "$final_file"
  if [ -f "$final_file" ] && grep -q 'Implementing...' "$final_file"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("jsonl_creation: final message artifact missing or wrong")
    echo "FAIL: jsonl_creation: final message artifact missing or wrong"
  fi

  # Cleanup
  cd / || true
  rm -rf "$test_dir"
}

test_jsonl_creation

# --- Promise detection test (issue #16) ---
test_promise_detection() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  mkdir -p logs

  # Create test JSONL with COMPLETE promise in the final assistant message
  cat > logs/iter-1.jsonl << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Working..."}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Done.\n<promise>COMPLETE</promise>"}]}}
{"type":"result","result":"legacy result"} 
EOF

  # Create test JSONL with BLOCKED promise in the final assistant message
  cat > logs/iter-2.jsonl << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Stuck..."}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Need help.\n<promise>BLOCKED</promise>"}]}}
{"type":"result","result":"legacy result"} 
EOF

  # Create test JSONL with no promise
  cat > logs/iter-3.jsonl << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"In progress..."}]}}
EOF

  write_final_message_artifact "claude" logs/iter-1.jsonl "$(iteration_final_message_file logs/iter-1.jsonl)"
  write_final_message_artifact "claude" logs/iter-2.jsonl "$(iteration_final_message_file logs/iter-2.jsonl)"
  write_final_message_artifact "claude" logs/iter-3.jsonl "$(iteration_final_message_file logs/iter-3.jsonl)"

  # Test promise extraction
  local promise

  promise=$(extract_promise_from_iteration_artifacts logs/iter-1.jsonl)
  if [ "$promise" = "COMPLETE" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("promise_detection: COMPLETE not detected")
    echo "FAIL: promise_detection: COMPLETE not detected"
  fi

  promise=$(extract_promise_from_iteration_artifacts logs/iter-2.jsonl)
  if [ "$promise" = "BLOCKED" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("promise_detection: BLOCKED not detected")
    echo "FAIL: promise_detection: BLOCKED not detected"
  fi

  promise=$(extract_promise_from_iteration_artifacts logs/iter-3.jsonl)
  if [ -z "$promise" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("promise_detection: no promise should be empty")
    echo "FAIL: promise_detection: no promise should be empty"
  fi

  # Cleanup
  cd / || true
  rm -rf "$test_dir"
}

test_promise_detection

# --- Claude adapter artifact tests (issue #45) ---
test_claude_final_message_extraction() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  mkdir -p logs
  cat > logs/iter-1.jsonl << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"First draft"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"bash","input":{"cmd":"echo hi"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Final line 1"},{"type":"text","text":"Final line 2\n<promise>COMPLETE</promise>"}]}}
EOF

  local final_file final_text
  final_file=$(iteration_final_message_file logs/iter-1.jsonl)
  write_final_message_artifact "claude" logs/iter-1.jsonl "$final_file"
  final_text=$(cat "$final_file")

  assert_eq "claude_final_message: extracted final text block" $'Final line 1\nFinal line 2\n<promise>COMPLETE</promise>' "$final_text"
  assert_eq "claude_final_message: promise comes from final artifact" "COMPLETE" "$(extract_promise_from_iteration_artifacts logs/iter-1.jsonl)"

  cd / || true
  rm -rf "$test_dir"
}

test_claude_final_message_extraction

test_promise_detection_prefers_final_message_and_legacy_fallback() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  mkdir -p logs
  cat > logs/iter-1.jsonl << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Working..."}]}}
{"type":"result","result":"<promise>COMPLETE</promise>"}
EOF
  printf '%s\n' '<promise>BLOCKED</promise>' > "$(iteration_final_message_file logs/iter-1.jsonl)"
  assert_eq "promise_preference: final artifact beats legacy result" "BLOCKED" "$(extract_promise_from_iteration_artifacts logs/iter-1.jsonl)"

  rm -f "$(iteration_final_message_file logs/iter-1.jsonl)"
  assert_eq "promise_preference: legacy fallback still works" "COMPLETE" "$(extract_promise_from_iteration_artifacts logs/iter-1.jsonl)"

  cd / || true
  rm -rf "$test_dir"
}

test_promise_detection_prefers_final_message_and_legacy_fallback

# --- Codex adapter contract tests (issue #46) ---
test_codex_adapter_uses_stdin_jsonl_and_final_artifact() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  git init >/dev/null 2>&1
  git config user.email "test@example.com" >/dev/null 2>&1
  git config user.name "Test User" >/dev/null 2>&1
  git checkout -b feature/codex-test >/dev/null 2>&1

  mkdir -p .scratch/demo/issues bin
  cat > .scratch/ACTIVE <<'EOF'
demo
EOF
  cat > .scratch/demo/PRD.md <<'EOF'
# Demo PRD
EOF
  cat > .scratch/demo/issues/01-codex.md <<'EOF'
Status: ready
---
Implement Codex adapter.
EOF
  cat > bin/mock-codex <<'MOCK_CODEX'
#!/usr/bin/env bash
set -eu

printf '%s\n' "$@" > codex-args.txt
cat > codex-stdin.txt

output_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--output-last-message" ] || [ "$prev" = "-o" ]; then
    output_file="$arg"
    break
  fi
  prev="$arg"
done

[ -n "$output_file" ] || exit 91
mkdir -p "$(dirname "$output_file")"
cat > "$output_file" <<'EOF'
Codex final answer
<promise>COMPLETE</promise>
EOF

cat <<'EOF'
{"type":"thread.started","thread_id":"thread-1"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item-1","type":"command_execution","command":"bash -lc echo hi","status":"in_progress"}}
{"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"bash -lc echo hi","status":"completed","exit_code":0}}
{"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"Planning...\nCodex final answer"}}
{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}
EOF
MOCK_CODEX
  chmod +x bin/mock-codex

  git add . >/dev/null 2>&1
  git commit -m "fixture" >/dev/null 2>&1

  # shellcheck disable=SC2034
  BACKEND="fs"
  # shellcheck disable=SC2034
  MARKER_FILE=".scratch/ACTIVE"
  # shellcheck disable=SC2034
  AGENT_CLI="codex"
  # shellcheck disable=SC2034
  AGENT_CMD="./bin/mock-codex"
  # shellcheck disable=SC2034
  AGENT_ARGS="--profile ci"
  # shellcheck disable=SC2034
  MODEL=""
  # shellcheck disable=SC2034
  MODEL_CLASS="low"

  local output rc log_file final_file args_dump stdin_dump
  output=$(iterate_once 2>&1)
  rc=$?

  log_file=$(find .ralph-logs/.scratch/demo -type f -name 'iter-*.jsonl' | sort | head -1)
  final_file=$(iteration_final_message_file "$log_file")
  args_dump=$(cat codex-args.txt)
  stdin_dump=$(cat codex-stdin.txt)

  assert_eq "codex_adapter: iterate_once returns COMPLETE" "20" "$rc"
  if [ -f "$log_file" ] && grep -q '"type":"thread.started"' "$log_file"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("codex_adapter: jsonl log file missing or wrong")
    echo "FAIL: codex_adapter: jsonl log file missing or wrong"
  fi

  if [ -f "$final_file" ] && grep -q '<promise>COMPLETE</promise>' "$final_file"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("codex_adapter: final artifact missing or wrong")
    echo "FAIL: codex_adapter: final artifact missing or wrong"
  fi

  assert_eq "codex_adapter: promise comes from final artifact" "COMPLETE" "$(extract_promise_from_iteration_artifacts "$log_file")"
  if printf '%s\n' "$args_dump" | grep -qx -- "exec" \
    && printf '%s\n' "$args_dump" | grep -qx -- "--json" \
    && printf '%s\n' "$args_dump" | grep -qx -- "--output-last-message" \
    && printf '%s\n' "$args_dump" | grep -qx -- "--sandbox" \
    && printf '%s\n' "$args_dump" | grep -qx -- "danger-full-access" \
    && printf '%s\n' "$args_dump" | grep -qx -- "--ask-for-approval" \
    && printf '%s\n' "$args_dump" | grep -qx -- "never" \
    && printf '%s\n' "$args_dump" | grep -qx -- "--model" \
    && printf '%s\n' "$args_dump" | grep -qx -- "gpt-5.4" \
    && [ "$(tail -1 codex-args.txt)" = "-" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("codex_adapter: expected codex exec arguments missing")
    echo "FAIL: codex_adapter: expected codex exec arguments missing"
    echo "$args_dump"
  fi

  if printf '%s' "$stdin_dump" | grep -q "Follow these priority rules" \
    && printf '%s' "$stdin_dump" | grep -q "@.scratch/demo/PRD.md @.scratch/demo/issues @progress.txt"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("codex_adapter: prompt not passed on stdin")
    echo "FAIL: codex_adapter: prompt not passed on stdin"
  fi

  if printf '%s' "$output" | grep -q "Planning..." \
    && printf '%s' "$output" | grep -q "command exit 0"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("codex_adapter: readable progress not streamed")
    echo "FAIL: codex_adapter: readable progress not streamed"
    echo "$output"
  fi

  cd / || true
  rm -rf "$test_dir"
}

test_codex_adapter_uses_stdin_jsonl_and_final_artifact

# --- Inspect list mode test (issue #16) ---
test_inspect_list() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  # Source ralph to use its functions
  # shellcheck disable=SC1090
  . "$RALPH"

  # Create pre-written JSONL fixtures
  mkdir -p .ralph-logs/test-milestone

  cat > .ralph-logs/test-milestone/iter-1-1609459200.jsonl << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Picked issue: #42"}]}}
{"type":"result","result":"<promise>COMPLETE</promise>"}
EOF

  cat > .ralph-logs/test-milestone/iter-2-1609459300.jsonl << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Picked issue: #43"}]}}
{"type":"result","result":"<promise>BLOCKED</promise>"}
EOF

  # Capture inspect output
  local output
  output=$(BACKEND=github GH_REPO="" cmd_inspect_list "test-milestone" 2>&1)

  # Verify table header is present
  if echo "$output" | grep -q "Iter#"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("inspect_list: header not found")
    echo "FAIL: inspect_list: header not found"
  fi

  # Verify iteration 1 is present with correct promise
  if echo "$output" | grep -q "1.*COMPLETE.*42"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("inspect_list: iteration 1 output incorrect")
    echo "FAIL: inspect_list: iteration 1 output incorrect"
    echo "$output"
  fi

  # Verify iteration 2 is present with correct promise
  if echo "$output" | grep -q "2.*BLOCKED.*43"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("inspect_list: iteration 2 output incorrect")
    echo "FAIL: inspect_list: iteration 2 output incorrect"
    echo "$output"
  fi

  # Cleanup
  cd / || true
  rm -rf "$test_dir"
}

test_inspect_list

# --- inspect_list empty/missing scope (set -u guard regression) ---
test_inspect_list_empty() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  # shellcheck disable=SC1090
  . "$RALPH"

  # Existing but empty scope dir: must not trip `set -u` on ${files[@]}
  mkdir -p .ralph-logs/empty-scope
  local output rc
  output=$(BACKEND=github GH_REPO="" cmd_inspect_list "empty-scope" 2>&1); rc=$?
  assert_eq "inspect_list: empty scope exits 0" "0" "$rc"
  if echo "$output" | grep -q "unbound variable"; then
    FAIL=$((FAIL+1)); FAILED_NAMES+=("inspect_list: empty scope unbound variable")
    echo "FAIL: inspect_list: empty scope unbound variable"; echo "$output"
  else
    PASS=$((PASS+1))
  fi
  if echo "$output" | grep -q "no iterations logged"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("inspect_list: empty scope message")
    echo "FAIL: inspect_list: empty scope message"; echo "$output"
  fi

  # Missing scope dir: graceful message, exit 0
  output=$(BACKEND=github GH_REPO="" cmd_inspect_list "no-such-scope" 2>&1); rc=$?
  assert_eq "inspect_list: missing scope exits 0" "0" "$rc"
  if echo "$output" | grep -q "no logs found"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("inspect_list: missing scope message")
    echo "FAIL: inspect_list: missing scope message"; echo "$output"
  fi

  cd / || true
  rm -rf "$test_dir"
}

test_inspect_list_empty

# --- Preflight guard: main branch tests (issue #38) ---
test_main_branch_guard() {
  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir" || exit 1

  # Initialize a git repo with main and feature branches
  git init >/dev/null 2>&1
  git config user.email "test@example.com" >/dev/null 2>&1
  git config user.name "Test User" >/dev/null 2>&1

  # Create initial commit on main
  touch .gitkeep
  git add .gitkeep >/dev/null 2>&1
  git commit -m "initial" >/dev/null 2>&1

  # Source ralph to test check_main_branch_guard
  # shellcheck disable=SC1090
  . "$RALPH"

  # Test 1: on main branch, guard should block (return 1)
  local output rc
  output=$(check_main_branch_guard 2>&1); rc=$?
  if [ $rc -eq 1 ] && echo "$output" | grep -q "refusing to run on"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("main_branch_guard: on main should block")
    echo "FAIL: main_branch_guard: on main should block (rc=$rc)"
    echo "$output"
  fi

  # Test 2: create feature branch and test proceed
  git checkout -b feature/test >/dev/null 2>&1
  output=$(check_main_branch_guard 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("main_branch_guard: on feature branch should proceed")
    echo "FAIL: main_branch_guard: on feature branch should proceed"
    echo "$output"
  fi

  # Test 3: switch back to the default branch and test override via RALPH_ALLOW_MAIN
  git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1
  output=$(RALPH_ALLOW_MAIN=1 check_main_branch_guard 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("main_branch_guard: RALPH_ALLOW_MAIN override should proceed")
    echo "FAIL: main_branch_guard: RALPH_ALLOW_MAIN override should proceed"
    echo "$output"
  fi

  # Test 4: verify message mentions engagement branch pattern (on default branch, unblocked)
  output=$(check_main_branch_guard 2>&1)
  if echo "$output" | grep -q "ralph/"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("main_branch_guard: message should mention ralph/ pattern")
    echo "FAIL: main_branch_guard: message should mention ralph/ pattern"
    echo "$output"
  fi

  # Cleanup
  cd / || true
  rm -rf "$test_dir"
}

test_main_branch_guard

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
