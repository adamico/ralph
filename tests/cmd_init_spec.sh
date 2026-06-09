#!/usr/bin/env bash
# Spec for cmd_init() in bin/ralph.
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

new_ws() { ws=$(mktemp -d); cd "$ws" || exit 1; }

# case 1: creates new conf with selected inputs
new_ws
out=$(cmd_init <<EOF
rtk
rtk
--fast
y
EOF
)
conf=$(cat .ralph.conf 2>/dev/null || echo "")
assert_contains "cmd_init/creates_conf" "Configuration added to .ralph.conf" "$out"
assert_contains "cmd_init/writes_cmd" "AGENT_CMD_rtk=\"rtk\"" "$conf"
assert_contains "cmd_init/writes_args" "AGENT_ARGS_rtk=\"--fast\"" "$conf"
assert_contains "cmd_init/writes_default" "DEFAULT_AGENT_CLI=\"rtk\"" "$conf"
cd /; rm -rf "$ws"

# case 2: appends to existing without making default
new_ws
echo "DEFAULT_AGENT_CLI=\"other\"" > .ralph.conf
out=$(cmd_init <<EOF
claude
claude
--profile x
n
EOF
)
conf=$(cat .ralph.conf)
assert_contains "cmd_init/appends_cmd" "AGENT_CMD_claude=\"claude\"" "$conf"
assert_contains "cmd_init/keeps_old_default" "DEFAULT_AGENT_CLI=\"other\"" "$conf"
cd /; rm -rf "$ws"

echo "cmd_init_spec: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
