#!/usr/bin/env bash
# Spec for pick_next_issue() in bin/ralph. Plain bash, no bats.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RALPH="$HERE/../bin/ralph"

# shellcheck disable=SC1090
. "$RALPH"

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

mk_fixture() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/issues"
  echo "$dir"
}

write_issue() {
  local file="$1" status="$2" blocked_by="${3:-}"
  {
    echo "Status: $status"
    [ -n "$blocked_by" ] && echo "Blocked-by: $blocked_by"
    echo "---"
    echo "body"
  } > "$file"
}

basename_of() { [ -n "$1" ] && basename "$1" || echo ""; }

# pick_next_issue echoes to stdout AND sets ALL_BLOCKED in the current
# shell. Command substitution would fork a subshell and lose the var, so
# capture stdout via a temp file instead.
pick() {
  local out
  out=$(mktemp)
  pick_next_issue "$1" > "$out"
  PICK=$(cat "$out")
  rm -f "$out"
}

# --- case 1: single ready, no deps -> picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-foo.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case1: picks lone ready" "01-foo.md" "$(basename_of "$got")"
assert_eq "case1: ALL_BLOCKED=0"    "0"         "$ALL_BLOCKED"
rm -rf "$d"

# --- case 2: lowest filename among readies wins ---
d=$(mk_fixture)
write_issue "$d/issues/02-b.md" ready
write_issue "$d/issues/01-a.md" ready
write_issue "$d/issues/03-c.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case2: lowest filename wins" "01-a.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 3: done issues skipped ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" done
write_issue "$d/issues/02-b.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case3: done skipped, next ready picked" "02-b.md" "$(basename_of "$got")"
assert_eq "case3: ALL_BLOCKED=0" "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 4: blocked-by undone dep => not picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-dep.md" ready
write_issue "$d/issues/02-needs.md" ready "01-dep"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case4: dep undone, picks dep itself" "01-dep.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 5: blocked-by dep done => downstream picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-dep.md" done
write_issue "$d/issues/02-needs.md" ready "01-dep"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case5: dep done, downstream picked" "02-needs.md" "$(basename_of "$got")"
rm -rf "$d"

# --- case 6: every ready is blocked => ALL_BLOCKED=1, empty pick ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" ready "99-missing"
write_issue "$d/issues/02-b.md" ready "01-a"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case6: all blocked => empty pick" "" "$got"
assert_eq "case6: ALL_BLOCKED=1"             "1" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 7: all done => empty pick, ALL_BLOCKED=0 ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" done
write_issue "$d/issues/02-b.md" done
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case7: all done => empty pick" "" "$got"
assert_eq "case7: ALL_BLOCKED=0"          "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 8: status 'blocked' not picked even with no deps ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" blocked
write_issue "$d/issues/02-b.md" ready
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case8: blocked skipped, ready picked" "02-b.md" "$(basename_of "$got")"
assert_eq "case8: ALL_BLOCKED=0 (b is pickable)" "0" "$ALL_BLOCKED"
rm -rf "$d"

# --- case 9: multi-dep, one undone => not picked ---
d=$(mk_fixture)
write_issue "$d/issues/01-a.md" done
write_issue "$d/issues/02-b.md" ready
write_issue "$d/issues/03-c.md" ready "01-a, 02-b"
ALL_BLOCKED=0
pick "$d"; got="$PICK"
assert_eq "case9: multi-dep with one undone -> picks earlier ready" "02-b.md" "$(basename_of "$got")"
rm -rf "$d"

# --- summary ---
echo
echo "ran $((PASS+FAIL)) assertions: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
