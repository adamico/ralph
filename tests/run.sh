#!/usr/bin/env bash
# Run every tests/*_spec.sh in isolation.
#
# Safety: specs are expected to mock the agent (AGENT_CMD -> a fake binary), but
# a bug or a future spec could leave AGENT_CMD pointing at a real agent CLI. A
# real invocation with an empty $HOME triggers a live OAuth/browser flow
# (notably `agy`/antigravity). To make a blanket run un-dangerous regardless of
# any single spec, we:
#   1. run each spec with an isolated, throwaway $HOME, and
#   2. prepend a shim dir that shadows the real agent binaries on $PATH with
#      stubs that fail loudly instead of authenticating.
#
# Usage: tests/run.sh [spec_name ...]   (default: all *_spec.sh)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# --- build the agent shim ------------------------------------------------
SHIM="$(mktemp -d)"
for bin in agy antigravity codex claude pi cursor; do
  cat > "$SHIM/$bin" <<'STUB'
#!/usr/bin/env bash
echo "tests/run.sh: refusing to exec real agent '$(basename "$0")' during tests" >&2
echo "  args: $*" >&2
echo "  A spec left AGENT_CMD pointing at a real CLI instead of a mock." >&2
exit 97
STUB
  chmod +x "$SHIM/$bin"
done
trap 'rm -rf "$SHIM"' EXIT

# --- select specs --------------------------------------------------------
if [ "$#" -gt 0 ]; then
  specs=()
  for name in "$@"; do
    case "$name" in
      */*) specs+=("$name") ;;
      *_spec.sh) specs+=("$HERE/$name") ;;
      *) specs+=("$HERE/${name}_spec.sh") ;;
    esac
  done
else
  specs=("$HERE"/*_spec.sh)
fi

# --- run -----------------------------------------------------------------
fails=0
for spec in "${specs[@]}"; do
  name="$(basename "$spec")"
  home="$(mktemp -d)"
  if HOME="$home" PATH="$SHIM:$PATH" bash "$spec" >/tmp/ralph-spec.$$ 2>&1; then
    echo "ok   $name"
  else
    rc=$?
    echo "FAIL $name (rc=$rc)"
    sed 's/^/    /' /tmp/ralph-spec.$$
    fails=$((fails+1))
  fi
  rm -rf "$home"
done
rm -f /tmp/ralph-spec.$$

echo
if [ "$fails" -ne 0 ]; then
  echo "$fails spec(s) failed"
  exit 1
fi
echo "all specs passed"
exit 0
