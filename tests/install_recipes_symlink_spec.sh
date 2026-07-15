#!/usr/bin/env bash
# Spec for install.sh recipes-symlink logic (ADR-0013). Plain bash, no bats.
# install.sh links ~/.ralph/recipes -> <repo>/recipes so native `ralph init`
# can read env + agent recipes.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$HERE/../install.sh"
REPO="$(cd "$HERE/.." && pwd)"
RECIPES_SRC="$REPO/recipes"

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
# real ~/.ralph. Side effects land under the temp dirs.
run_install() {
  local home="$1"
  HOME="$home" PREFIX="$home/.local" bash "$INSTALL" >/dev/null 2>&1
}

# --- case 1: clean HOME => binary + recipes link created ---
d=$(mktemp -d)
run_install "$d"; rc=$?
assert_eq "case1: install exits 0" "0" "$rc"
ok "case1: ralph binary installed"  test -x "$d/.local/bin/ralph"
ok "case1: recipes link is a symlink" test -L "$d/.ralph/recipes"
assert_eq "case1: link points at repo recipes" \
  "$RECIPES_SRC" "$(readlink "$d/.ralph/recipes")"
ok "case1: link resolves to environments/" test -d "$d/.ralph/recipes/environments"
ok "case1: link resolves to agents/"       test -d "$d/.ralph/recipes/agents"
rm -rf "$d"

# --- case 2: pre-existing real dir => replaced by symlink (guard) ---
d=$(mktemp -d)
mkdir -p "$d/.ralph/recipes"
echo "stale hand-copied content" > "$d/.ralph/recipes/leftover.txt"
run_install "$d"
ok "case2: stale dir replaced by symlink" test -L "$d/.ralph/recipes"
assert_eq "case2: link points at repo recipes" \
  "$RECIPES_SRC" "$(readlink "$d/.ralph/recipes")"
rm -rf "$d"

# --- case 3: pre-existing symlink (old target) => repointed ---
d=$(mktemp -d)
mkdir -p "$d/.ralph" "$d/old-target"
ln -sfn "$d/old-target" "$d/.ralph/recipes"
run_install "$d"
ok "case3: still a symlink" test -L "$d/.ralph/recipes"
assert_eq "case3: repointed at repo recipes" \
  "$RECIPES_SRC" "$(readlink "$d/.ralph/recipes")"
rm -rf "$d"

# --- case 4: idempotent => second run leaves an identical link ---
d=$(mktemp -d)
run_install "$d"
run_install "$d"; rc=$?
assert_eq "case4: second run exits 0" "0" "$rc"
assert_eq "case4: link still points at repo recipes" \
  "$RECIPES_SRC" "$(readlink "$d/.ralph/recipes")"
rm -rf "$d"

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
