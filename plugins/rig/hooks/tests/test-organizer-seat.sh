#!/bin/bash
# Regression suite for organizer-seat.sh (PreToolUse Edit|Write|NotebookEdit).
# Fires only while an agy run is alive, and only once per session.
# A fake `agy` on PATH stands in for a real run, so the suite costs no quota.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/organizer-seat.sh"
fails=0
ORGANIZER_SEAT_STATE_DIR=$(mktemp -d); export ORGANIZER_SEAT_STATE_DIR
FAKEBIN=$(mktemp -d)
# Kill only our own staged process. `pkill -x agy` would reap every real agy run on the
# machine, including other sessions' — the generic-kill antipattern farm-out warns about.
FAKE_PID=""
cleanup() { [ -n "$FAKE_PID" ] && kill -9 "$FAKE_PID" 2>/dev/null; rm -rf "$ORGANIZER_SEAT_STATE_DIR" "$FAKEBIN"; }
trap cleanup EXIT

check() { # name expected_rc session
  local name=$1 want=$2 sid=$3 got
  printf '{"session_id":"%s"}' "$sid" | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got)"; fails=$((fails + 1))
  fi
}

# A real agy run would cost a quota slot, so stand one up under the same process name.
printf '#!/bin/bash\nsleep 30\n' > "$FAKEBIN/agy"
chmod +x "$FAKEBIN/agy"

# Someone else's agy run makes the quiet case untestable; skip rather than kill theirs.
if pgrep -x agy >/dev/null 2>&1; then
  echo "SKIP: silent when no agy run is alive (a real agy run is active)"
else
  check "silent when no agy run is alive" 0 s0
fi

# stdio detached: a background child holding the pipe open hangs the whole suite
"$FAKEBIN/agy" >/dev/null 2>&1 &
FAKE_PID=$!
sleep 1
pgrep -x agy >/dev/null || { echo "FAIL: could not stage a fake agy run"; exit 1; }

check "fires on the first edit while a run is live" 2 s1
check "stays quiet for the rest of that session"    0 s1
check "a different session gets its own nudge"      2 s2

# Guard reporting: when blocking, exits 2 even with mage absent, and stderr contains guard id
err=$(printf '{"session_id":"s_guard"}' | PATH="$FAKEBIN:/usr/bin:/bin" "$HOOK" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q '^mage:rig/guard/organizer-seat$' <<<"$err"; then
  echo "PASS: blocks with exit 2 and guard id on stderr when mage absent"
else
  echo "FAIL: guard report check failed (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

kill -9 "$FAKE_PID" 2>/dev/null; FAKE_PID=""; sleep 1
if pgrep -x agy >/dev/null 2>&1; then
  echo "SKIP: silent again once the run ends (a real agy run is active)"
else
  check "silent again once the run ends" 0 s3
fi

[ "$fails" -eq 0 ] && echo && echo "all organizer-seat hook tests passed"
exit "$fails"
