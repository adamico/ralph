#!/usr/bin/env bash
# Install ralph to ~/.local/bin (override with PREFIX=/usr/local).
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
DEST="$PREFIX/bin"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$DEST"
install -m 0755 "$SRC_DIR/bin/ralph" "$DEST/ralph"
echo "installed: $DEST/ralph"

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "note: $DEST is not on \$PATH" ;;
esac
