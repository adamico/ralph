#!/usr/bin/env bash
# Run every tests/*_spec.sh in isolation.
#
# Safety + isolation: specs are expected to mock the agent (AGENT_CMD -> a fake
# binary), but a bug or a future spec could leave AGENT_CMD pointing at a real
# agent CLI. A real invocation with an empty $HOME triggers a live OAuth/browser
# flow (notably `agy`/antigravity). Specs also `. bin/ralph`, which sources
# `./.ralph.conf` (bin/ralph:513) from the current directory — so running from
# the repo root leaks the developer's local config (e.g. AGENT_CMD_claude) into
# resolution and fails otherwise-correct assertions. To make a blanket run both
# un-dangerous and reproducible regardless of any single spec, we run each spec:
#   1. from a throwaway empty cwd (no local ./.ralph.conf is picked up),
#   2. with an isolated, throwaway $HOME, and
#   3. with a shim dir prepended to $PATH that shadows the real agent binaries
#      with stubs that fail loudly instead of authenticating.
# Specs locate bin/ralph via an absolute path derived from $0, so cwd is free.
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
  cwd="$(mktemp -d)"
  spec_abs="$(cd "$(dirname "$spec")" && pwd)/$(basename "$spec")"
  if ( cd "$cwd" && HOME="$home" PATH="$SHIM:$PATH" bash "$spec_abs" ) >/tmp/ralph-spec.$$ 2>&1; then
    echo "ok   $name"
  else
    rc=$?
    echo "FAIL $name (rc=$rc)"
    sed 's/^/    /' /tmp/ralph-spec.$$
    fails=$((fails+1))
  fi
  rm -rf "$home" "$cwd"
done
rm -f /tmp/ralph-spec.$$

echo
if [ "$fails" -ne 0 ]; then
  echo "$fails spec(s) failed"
  exit 1
fi
echo "all specs passed"
exit 0
