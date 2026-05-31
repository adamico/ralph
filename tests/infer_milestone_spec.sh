#!/usr/bin/env bash
# Spec for infer_milestone_gh interactive picker (multiple open milestones).
#
# Regression for the silent-hang bug: the function is always called via
# $(infer_milestone_gh), so the picker menu + "Select milestone" prompt must
# go to STDERR (else they are captured and the user sees nothing while `read`
# blocks). Only the chosen title may go to stdout. Requires a real TTY, so we
# drive it through a pseudo-terminal with python3.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RALPH="$SCRIPT_DIR/bin/ralph"

PASS=0; FAIL=0
pass() { echo "PASS $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL $1"; FAIL=$((FAIL+1)); }

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP infer_milestone_spec (python3 not available)"
  exit 0
fi

# Drive infer_milestone_gh under a pty. Stubs gh to emit two milestones,
# sends the keystroke "2", captures stdout (the return value) separately
# from the pty stream (which carries the stderr menu).
run_pick() {
  local choice="$1"
  python3 - "$RALPH" "$choice" <<'PY'
import os, pty, sys, time, select
ralph, choice = sys.argv[1], sys.argv[2]
r_out, w_out = os.pipe()  # child stdout (the captured return value)
pid, fd = pty.fork()
if pid == 0:
    os.close(r_out)
    os.dup2(w_out, 3)  # expose return-value pipe as fd 3
    script = (
        'gh(){ echo \'[{"title":"alpha"},{"title":"beta"}]\'; }; '
        '. "%s"; '
        'sel=$(infer_milestone_gh); '
        'printf "%%s" "$sel" >&3' % ralph
    )
    os.execvp("bash", ["bash", "-c", script])
os.close(w_out)
time.sleep(0.4)
os.write(fd, (choice + "\n").encode())
menu = b""
while True:
    r, _, _ = select.select([fd], [], [], 2)
    if not r:
        break
    try:
        d = os.read(fd, 1024)
    except OSError:
        break
    if not d:
        break
    menu += d
ret = b""
while True:
    d = os.read(r_out, 1024)
    if not d:
        break
    ret += d
# Line 1: stdout return value. Line 2..: marker + the pty(stderr) menu text.
sys.stdout.write("RET:" + ret.decode(errors="replace") + "\n")
sys.stdout.write("MENU:" + menu.decode(errors="replace").replace("\n", "\\n"))
PY
}

out=$(run_pick 2)
ret=$(printf '%s\n' "$out" | sed -n 's/^RET://p')
menu=$(printf '%s\n' "$out" | sed -n 's/^MENU://p')

# 1. Return value is exactly the chosen milestone (not all of them, not empty).
if [ "$ret" = "beta" ]; then
  pass "picker returns the selected milestone on stdout"
else
  fail "picker stdout should be 'beta', got '[$ret]'"
fi

# 2. The menu/prompt is visible (went to stderr → pty), not swallowed.
case "$menu" in
  *"Multiple open milestones"*"Select milestone"*)
    pass "picker menu + prompt are written to stderr (visible)" ;;
  *)
    fail "picker menu/prompt missing from stderr stream: [$menu]" ;;
esac

echo "infer_milestone_spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
