#!/usr/bin/env bash
# Install ralph to ~/.local/bin (override with PREFIX=/usr/local).
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
DEST="$PREFIX/bin"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$DEST"
# Symlink (not copy) so repo updates take effect without reinstalling.
# Replace a real file left by a prior copy-based install first.
[ -e "$DEST/ralph" ] && [ ! -L "$DEST/ralph" ] && rm -f "$DEST/ralph"
ln -sfn "$SRC_DIR/bin/ralph" "$DEST/ralph"
echo "linked: $DEST/ralph -> $SRC_DIR/bin/ralph"

RALPH_RECIPES="$HOME/.ralph/recipes"
mkdir -p "$HOME/.ralph"
[ -e "$RALPH_RECIPES" ] && [ ! -L "$RALPH_RECIPES" ] && rm -rf "$RALPH_RECIPES"
ln -sfn "$SRC_DIR/recipes" "$RALPH_RECIPES"
echo "linked: $RALPH_RECIPES -> $SRC_DIR/recipes"

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "note: $DEST is not on \$PATH" ;;
esac
