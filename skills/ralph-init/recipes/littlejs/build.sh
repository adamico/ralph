#!/usr/bin/env bash
# Build the `<repo>-littlejs` sbx template (standard tier).
#
# Creates a Node.js sandbox with vitest and eslint pre-configured.
# Snapshots a `node:20` image with npm dependencies pre-installed
# so ralph can run tests and lint without per-iteration setup cost.
#
# Re-run any time package.json or system deps change.

set -euo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-claude-littlejs}"
TEMPLATE_TAG="${TEMPLATE_TAG:-littlejs}"

echo ">> building $TEMPLATE_TAG (node:20)"

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

# Create or verify sandbox exists
if ! sbx ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$SANDBOX_NAME"; then
  echo ">> creating base sandbox"
  sbx create --name "$SANDBOX_NAME" --image "node:20" .
fi

echo ">> installing npm dependencies"
sbx exec -i "$SANDBOX_NAME" bash -c 'cd /workspace && npm ci' || {
  echo "Warning: npm ci failed, trying npm install" >&2
  sbx exec -i "$SANDBOX_NAME" bash -c 'cd /workspace && npm install' || true
}

echo ">> built $TEMPLATE_TAG template: $SANDBOX_NAME"
echo "Use: sbx run $SANDBOX_NAME -- <command>"
