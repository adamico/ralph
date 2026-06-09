#!/usr/bin/env bash
# Spec for Agent CLI config/model resolution in bin/ralph. Plain bash, no bats.
# shellcheck disable=SC2034
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RALPH="$HERE/../bin/ralph"

# shellcheck disable=SC1090
. "$RALPH"

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); }

fail() {
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("$1")
  echo "FAIL: $1"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass
  else
    fail "$label"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass
  else
    fail "$label"
    echo "  expected to contain: '$needle'"
    echo "  actual:              '$haystack'"
  fi
}

assert_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass
  else
    fail "$label"
    echo "  expected rc: '$expected'"
    echo "  actual rc:   '$actual'"
  fi
}

reset_agent_cfg() {
  AGENT_CLI=""
  AGENT_CMD=""
  AGENT_ARGS=""
  CLAUDE_CMD=""
  MODEL=""
  MODEL_CLASS="low"
  LEGACY_CLAUDE_CMD_WARNED=0
  RESOLVED_AGENT_CLI=""
  RESOLVED_AGENT_CMD=""
  RESOLVED_AGENT_ARGS=""
  RESOLVED_MODEL=""
  RESOLVED_MODEL_SOURCE=""
  RESOLVED_MODEL_CLASS=""
  RESOLVED_MODEL_DISPLAY=""
}

run_capture() {
  local fn="$1"
  shift
  local out
  out=$(mktemp)
  "$fn" "$@" >"$out" 2>&1
  RUN_RC=$?
  RUN_OUT=$(cat "$out")
  rm -f "$out"
}

reset_agent_cfg
run_capture resolve_agent_cli_config
assert_rc "default resolve_agent_cli_config rc" 0 "$RUN_RC"
assert_eq "default cli" "claude" "$RESOLVED_AGENT_CLI"
assert_eq "default cmd" "claude" "$RESOLVED_AGENT_CMD"
assert_eq "default warning absent" "" "$RUN_OUT"
run_capture resolve_model_config "$RESOLVED_AGENT_CLI"
assert_rc "default resolve_model_config rc" 0 "$RUN_RC"
assert_eq "default model" "sonnet" "$RESOLVED_MODEL"
assert_eq "default model display" "sonnet (MODEL_CLASS=low default)" "$RESOLVED_MODEL_DISPLAY"

reset_agent_cfg
AGENT_CLI="codex"
run_capture resolve_agent_cli_config
assert_rc "codex config rc" 0 "$RUN_RC"
assert_eq "codex default cmd" "codex" "$RESOLVED_AGENT_CMD"
run_capture resolve_model_config "$RESOLVED_AGENT_CLI"
assert_rc "codex model rc" 0 "$RUN_RC"
assert_eq "codex low model" "gpt-5.4-mini" "$RESOLVED_MODEL"

reset_agent_cfg
AGENT_CLI="pi"
run_capture resolve_agent_cli_config
assert_rc "pi config rc" 0 "$RUN_RC"
run_capture resolve_model_config "$RESOLVED_AGENT_CLI"
assert_rc "pi model rc" 0 "$RUN_RC"
assert_eq "pi model omitted" "" "$RESOLVED_MODEL"
assert_eq "pi manifest value" "provider default (MODEL_CLASS=low; ralph omits --model)" "$(agent_model_manifest_value)"

reset_agent_cfg
AGENT_CLI="antigravity"
run_capture resolve_agent_cli_config
assert_rc "antigravity config rc" 0 "$RUN_RC"
run_capture resolve_model_config "$RESOLVED_AGENT_CLI"
assert_rc "antigravity model rc" 0 "$RUN_RC"
assert_eq "antigravity low model" "Gemini 3.5 Flash (Low)" "$RESOLVED_MODEL"
assert_eq "antigravity manifest value" "Gemini 3.5 Flash (Low)" "$(agent_model_manifest_value)"

reset_agent_cfg
AGENT_CLI="codex"
MODEL="gpt-5.7-preview"
run_capture resolve_agent_cli_config
assert_rc "explicit config rc" 0 "$RUN_RC"
run_capture resolve_model_config "$RESOLVED_AGENT_CLI"
assert_rc "explicit model rc" 0 "$RUN_RC"
assert_eq "explicit model wins" "gpt-5.7-preview" "$RESOLVED_MODEL"
assert_eq "explicit source label" "gpt-5.7-preview (explicit)" "$RESOLVED_MODEL_DISPLAY"

reset_agent_cfg
CLAUDE_CMD="/tmp/legacy-claude"
run_capture resolve_agent_cli_config
assert_rc "legacy config rc" 0 "$RUN_RC"
assert_eq "legacy cli" "claude" "$RESOLVED_AGENT_CLI"
assert_eq "legacy cmd" "/tmp/legacy-claude" "$RESOLVED_AGENT_CMD"
assert_contains "legacy warning emitted" "CLAUDE_CMD is deprecated" "$RUN_OUT"
run_capture resolve_agent_cli_config
assert_rc "legacy second rc" 0 "$RUN_RC"
assert_eq "legacy warning only once" "" "$RUN_OUT"

reset_agent_cfg
AGENT_CLI="codex"
AGENT_CMD="/tmp/codex-wrapper"
AGENT_ARGS="--profile staging"
CLAUDE_CMD="/tmp/legacy-claude"
run_capture resolve_agent_cli_config
assert_rc "new command precedence rc" 0 "$RUN_RC"
assert_eq "new command precedence cli" "codex" "$RESOLVED_AGENT_CLI"
assert_eq "new command precedence cmd" "/tmp/codex-wrapper" "$RESOLVED_AGENT_CMD"
assert_eq "new command precedence args" "--profile staging" "$RESOLVED_AGENT_ARGS"
assert_eq "new command precedence warning absent" "" "$RUN_OUT"

reset_agent_cfg
AGENT_CLI="not-real"
run_capture resolve_agent_cli_config
assert_rc "unsupported cli rc" 1 "$RUN_RC"
assert_contains "unsupported cli message" "unsupported AGENT_CLI 'not-real'" "$RUN_OUT"

reset_agent_cfg
AGENT_CMD="/tmp/wrapper"
run_capture resolve_agent_cli_config
assert_rc "missing cli rc" 1 "$RUN_RC"
assert_contains "missing cli message" "AGENT_CMD is set but AGENT_CLI is missing" "$RUN_OUT"

reset_agent_cfg
AGENT_CLI="claude"
MODEL_CLASS="medium"
run_capture resolve_agent_cli_config
assert_rc "bad model_class config rc" 0 "$RUN_RC"
run_capture resolve_model_config "$RESOLVED_AGENT_CLI"
assert_rc "bad model_class rc" 1 "$RUN_RC"
assert_contains "bad model_class message" "unsupported MODEL_CLASS 'medium'" "$RUN_OUT"

echo
echo "agent_cli_config_spec: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
