#!/usr/bin/env bash
# Build the `<repo>-littlejs` sbx sandbox (standard tier).
#
# Agent-specific sandbox mounting the GIT ROOT (so the agent has .git for
# commit/push and the harness can autodetect the branch). The default adapter is
# Codex and therefore starts from Docker's Codex sandbox template; this script
# layers Node.js 20 project tooling on top. Project deps are NOT pre-installed
# here — the dual-mode `run_tests` harness builds clean linux deps via `npm ci`
# inside a fresh /tmp clone (remote mode), so a host-mounted node_modules is never
# shared into the linux container.
#
# Re-run if the base image or system deps change.

set -euo pipefail

# Sandbox mounts the git root, not the port dir, so the agent has .git.
GIT_ROOT="$(git rev-parse --show-toplevel)"
REPO="$(basename "$GIT_ROOT")"
SANDBOX_NAME="${SANDBOX_NAME:-${REPO}-littlejs}"
AGENT_CLI="${AGENT_CLI:-codex}"

case "$AGENT_CLI" in
  codex|claude|pi) ;;
  *)
    echo "Error: unsupported AGENT_CLI '$AGENT_CLI' (expected codex, claude, or pi)." >&2
    exit 1
    ;;
esac

echo ">> building sandbox $SANDBOX_NAME (agent: $AGENT_CLI, mount $GIT_ROOT)"

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

# Create the sandbox if it does not already exist. Agent-specific sbx creation
# uses Docker's maintained sandbox template for that adapter (Codex by default).
if ! sbx ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$SANDBOX_NAME"; then
  echo ">> creating sandbox from $AGENT_CLI template"
  sbx create --name "$SANDBOX_NAME" "$AGENT_CLI" "$GIT_ROOT"
fi

# Ensure git + LittleJS tooling are present inside the sandbox. The Agent CLI
# executable comes from the agent-specific template; Claude can be installed here
# for legacy/custom templates. Codex auth should be stored with:
#   sbx secret set -g openai --oauth
# API key fallback:
#   echo "$OPENAI_API_KEY" | sbx secret set -g openai
echo ">> ensuring git + Node.js 20 tooling"
sbx exec -i "$SANDBOX_NAME" bash -c "
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive
  if ! command -v git >/dev/null 2>&1; then
    apt-get update
    apt-get install -y git
  fi
  if ! command -v node >/dev/null 2>&1 || ! node --version | grep -q '^v20\\.'; then
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -d -m 0755 /etc/apt/keyrings
    rm -f /etc/apt/keyrings/nodesource.gpg
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main' > /etc/apt/sources.list.d/nodesource.list
    apt-get update
    apt-get install -y nodejs
  fi
  if [ '$AGENT_CLI' = claude ] && ! command -v claude >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code
  fi
"

echo ">> built sandbox: $SANDBOX_NAME"
echo "Use: sbx run $SANDBOX_NAME -- <command>"
