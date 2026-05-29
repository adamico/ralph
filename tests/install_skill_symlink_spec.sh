#!/usr/bin/env bash
# Spec for install.sh skill-symlink logic (ADR-0003). Plain bash, no bats.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$HERE/../install.sh"
REPO="$(cd "$HERE/.." && pwd)"
SKILL_SRC="$REPO/skills/ralph-init"

PASS=0
FAIL=0
FAILED_NAMES=()

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
  fi
}

ok() {
  local label="$1"; shift
  if "$@"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$label")
    echo "FAIL: $label"
  fi
}

# Run install.sh against an isolated HOME + PREFIX so we never touch the
# real ~/.claude. Echoes nothing; side effects land under the temp dirs.
run_install() {
  local home="$1"
  HOME="$home" PREFIX="$home/.local" bash "$INSTALL" >/dev/null 2>&1
}

# --- case 1: no ~/.claude/skills => no link, install still succeeds ---
d=$(mktemp -d)
run_install "$d"; rc=$?
assert_eq "case1: install exits 0 without skills dir" "0" "$rc"
ok "case1: ralph binary installed" test -x "$d/.local/bin/ralph"
ok "case1: no skill link created"  test ! -e "$d/.claude/skills/ralph-init"
rm -rf "$d"

# --- case 2: skills dir present => symlink created, points at repo ---
d=$(mktemp -d)
mkdir -p "$d/.claude/skills"
run_install "$d"
ok "case2: link is a symlink" test -L "$d/.claude/skills/ralph-init"
assert_eq "case2: link points at repo skill" \
  "$SKILL_SRC" "$(readlink "$d/.claude/skills/ralph-init")"
ok "case2: link resolves to SKILL.md" test -f "$d/.claude/skills/ralph-init/SKILL.md"
rm -rf "$d"

# --- case 3: pre-existing real dir => replaced by symlink (guard) ---
d=$(mktemp -d)
mkdir -p "$d/.claude/skills/ralph-init"
echo "stale hand-copied content" > "$d/.claude/skills/ralph-init/SKILL.md"
run_install "$d"
ok "case3: stale dir replaced by symlink" test -L "$d/.claude/skills/ralph-init"
assert_eq "case3: link points at repo skill" \
  "$SKILL_SRC" "$(readlink "$d/.claude/skills/ralph-init")"
rm -rf "$d"

# --- case 4: pre-existing symlink (e.g. old target) => repointed ---
d=$(mktemp -d)
mkdir -p "$d/.claude/skills" "$d/old-target"
ln -sfn "$d/old-target" "$d/.claude/skills/ralph-init"
run_install "$d"
ok "case4: still a symlink" test -L "$d/.claude/skills/ralph-init"
assert_eq "case4: repointed at repo skill" \
  "$SKILL_SRC" "$(readlink "$d/.claude/skills/ralph-init")"
rm -rf "$d"

# --- case 5: idempotent => second run leaves an identical link ---
d=$(mktemp -d)
mkdir -p "$d/.claude/skills"
run_install "$d"
run_install "$d"; rc=$?
assert_eq "case5: second run exits 0" "0" "$rc"
assert_eq "case5: link still points at repo skill" \
  "$SKILL_SRC" "$(readlink "$d/.claude/skills/ralph-init")"
rm -rf "$d"

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
