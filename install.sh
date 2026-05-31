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
