#!/usr/bin/env bash
# Spec for cmd_init() in bin/ralph (native recipe-driven init, ADR-0013).
#
# Prompt order for a fresh conf:
#   BACKEND -> [env: recipe menu or manual TEST_CMD/LINT_CMD]
#           -> [agent: recipe menu or manual CLI/CMD/ARGS] -> make-default
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
  fi
}

assert_absent() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label (unexpected '$needle')"
  fi
}

new_ws() { ws=$(mktemp -d); cd "$ws" || exit 1; }
end_ws() { cd /; rm -rf "$ws"; }

# Isolate HOME so no real ~/.ralph/recipes leaks in. Each case that needs
# recipes builds them under $HOME/.ralph/recipes.
fresh_home() { HOME=$(mktemp -d); }

# --- case 1: no recipes -> manual env + manual agent, new conf ----------
fresh_home
new_ws
out=$(cmd_init <<EOF
fs
./run_tests
/lint
rtk
rtk
--fast
y
EOF
)
conf=$(cat .ralph.conf 2>/dev/null || echo "")
assert_contains "manual/creates_conf"  "Configuration added to .ralph.conf" "$out"
assert_contains "manual/backend"        "BACKEND=\"fs\""            "$conf"
assert_contains "manual/test_cmd"       "TEST_CMD=\"./run_tests\""  "$conf"
assert_contains "manual/writes_cmd"     "AGENT_CMD_rtk=\"rtk\""     "$conf"
assert_contains "manual/writes_args"    "AGENT_ARGS_rtk=\"--fast\"" "$conf"
assert_contains "manual/writes_default" "DEFAULT_AGENT_CLI=\"rtk\"" "$conf"
rm -rf "$HOME"; end_ws

# --- case 2: existing conf, decline default -----------------------------
fresh_home
new_ws
cat > .ralph.conf <<EOF
BACKEND="fs"
TEST_CMD="./run_tests"
DEFAULT_AGENT_CLI="other"
EOF
out=$(cmd_init <<EOF
claude
claude
--profile x
n
EOF
)
conf=$(cat .ralph.conf)
assert_contains "append/writes_cmd"      "AGENT_CMD_claude=\"claude\""     "$conf"
assert_contains "append/keeps_old_default" "DEFAULT_AGENT_CLI=\"other\""   "$conf"
rm -rf "$HOME"; end_ws

# --- case 3: agent recipe applied -> MODEL_CLASS written (regression) ----
fresh_home
mkdir -p "$HOME/.ralph/recipes/agents/claude-local"
cat > "$HOME/.ralph/recipes/agents/claude-local/agent.conf" <<EOF
AGENT_CLI="claude"
AGENT_CMD="claude"
AGENT_ARGS=""
MODEL_CLASS="high"
EOF
new_ws
cat > .ralph.conf <<EOF
BACKEND="fs"
TEST_CMD="./run_tests"
EOF
# agent menu present (1 recipe); pick "1", then make-default "y"
out=$(cmd_init <<EOF
1
y
EOF
)
conf=$(cat .ralph.conf)
assert_contains "recipe/applies_agent"  "AGENT_CMD_claude=\"claude\"" "$conf"
assert_contains "recipe/writes_model"   "MODEL_CLASS=\"high\""        "$conf"
rm -rf "$HOME"; end_ws

# --- case 4: env recipe applied -> env.conf appended + harness copied ----
fresh_home
mkdir -p "$HOME/.ralph/recipes/environments/demo"
cat > "$HOME/.ralph/recipes/environments/demo/env.conf" <<EOF
TEST_CMD="demo-test"
LINT_CMD="demo-lint"
EOF
printf '#!/bin/sh\necho hi\n' > "$HOME/.ralph/recipes/environments/demo/run_tests"
new_ws
# fresh conf: BACKEND, env menu (no detection) -> pick "1", agent manual
out=$(cmd_init <<EOF
fs
1
rtk
rtk

y
EOF
)
conf=$(cat .ralph.conf)
assert_contains "env/test_cmd"    "TEST_CMD=\"demo-test\"" "$conf"
assert_contains "env/lint_cmd"    "LINT_CMD=\"demo-lint\"" "$conf"
assert_contains "env/copies_harness" "hi" "$(cat run_tests 2>/dev/null || echo '')"
assert_absent   "env/no_manual_test" "Enter TEST_CMD" "$out"
rm -rf "$HOME"; end_ws

echo "cmd_init_spec: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
