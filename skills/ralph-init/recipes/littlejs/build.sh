#!/usr/bin/env bash
# Build the `<repo>-littlejs` sbx sandbox (standard tier).
#
# Bare node:20 sandbox mounting the GIT ROOT (so the agent has .git for
# commit/push and the harness can autodetect the branch). Project deps are NOT
# pre-installed here — the dual-mode `run_tests` harness builds clean linux deps
# via `npm ci` inside a fresh /tmp clone (remote mode), so a host-mounted
# node_modules is never shared into the linux container.
#
# Re-run if the base image or system deps change.

set -euo pipefail

# Sandbox mounts the git root, not the port dir, so the agent has .git.
GIT_ROOT="$(git rev-parse --show-toplevel)"
REPO="$(basename "$GIT_ROOT")"
SANDBOX_NAME="${SANDBOX_NAME:-${REPO}-littlejs}"

echo ">> building sandbox $SANDBOX_NAME (node:20, mount $GIT_ROOT)"

# Ensure sbx is available
if ! command -v sbx >/dev/null 2>&1; then
  echo "Error: sbx CLI not found. Install it and try again." >&2
  exit 1
fi

# Ensure docker is running
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon not running." >&2
  exit 1
fi

# Create the sandbox if it does not already exist
if ! sbx ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$SANDBOX_NAME"; then
  echo ">> creating sandbox"
  sbx create --name "$SANDBOX_NAME" --image "node:20" "$GIT_ROOT"
fi

# Ensure git + an Agent CLI executable are present inside the sandbox.
# This recipe installs Claude Code as the example adapter used by the generated
# AGENT_CMD="sbx run $SANDBOX_NAME -- claude".
echo ">> ensuring git + Agent CLI executable"
sbx exec -i "$SANDBOX_NAME" bash -c '
  command -v git >/dev/null 2>&1 || (apt-get update && apt-get install -y git)
  command -v claude >/dev/null 2>&1 || npm install -g @anthropic-ai/claude-code
'

echo ">> built sandbox: $SANDBOX_NAME"
echo "Use: sbx run $SANDBOX_NAME -- <command>"
