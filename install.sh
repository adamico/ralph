#!/usr/bin/env bash
# Install ralph to ~/.local/bin (override with PREFIX=/usr/local).
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
DEST="$PREFIX/bin"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$DEST"
install -m 0755 "$SRC_DIR/bin/ralph" "$DEST/ralph"
echo "installed: $DEST/ralph"

# Symlink tool-coupled skills into Claude Code (ADR-0003), only if present.
SKILLS_DIR="$HOME/.claude/skills"
if [ -d "$SKILLS_DIR" ]; then
  LINK="$SKILLS_DIR/ralph-init"
  # ln -sfn won't replace a real (non-symlink) dir left by a prior hand-copy;
  # remove it first so the link always points at this repo.
  [ -e "$LINK" ] && [ ! -L "$LINK" ] && rm -rf "$LINK"
  ln -sfn "$SRC_DIR/skills/ralph-init" "$LINK"
  echo "linked: $LINK -> $SRC_DIR/skills/ralph-init"
fi

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "note: $DEST is not on \$PATH" ;;
esac
