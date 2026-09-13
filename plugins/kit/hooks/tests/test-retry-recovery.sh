#!/bin/bash
# Re-arming a watcher after a rate-limit notice was already recorded used to lose the
# auto-retry silently: the new process read the same updated_at, skipped the arming path,
# and left retry_at at 0 with no event saying so. Silence read exactly like an armed wait.
# These run the REAL watcher against a stubbed gh. See claude-kit#28.
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHER="$SELF_DIR/../../skills/pr-watch/watch-coderabbit.sh"
FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }
[ -f "$WATCHER" ] || { echo "cannot find $WATCHER"; exit 1; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export CR_WATCH_STATE_DIR="$SANDBOX/state"
mkdir -p "$CR_WATCH_STATE_DIR"
POSTED="$SANDBOX/posted"

# A notice timestamped well in the past, so an armed retry is already due: the recovery
# path must fire it now rather than restart the clock from the moment it recovered.
NOTICE_TS=$(date -u -d '-90 minutes' +%Y-%m-%dT%H:%M:%SZ)
cat > "$SANDBOX/gh" <<STUB
#!/bin/bash
POSTED="$POSTED"
NOTICE_TS="$NOTICE_TS"
STUB
cat >> "$SANDBOX/gh" <<'STUB'
args="$*"
case "$args" in
  *"pr view"*)                 echo OPEN; exit 0 ;;
  *"pr checks"*)               exit 0 ;;
  *"contents/.coderabbit.yaml"*) echo '{"name":".coderabbit.yaml"}'; exit 0 ;;
  *"-f body="*)                printf '%s\n' "$args" >> "$POSTED"; echo '{}'; exit 0 ;;
  *"/pulls/"*"/comments"*)     echo '[]'; exit 0 ;;
  *"/issues/"*"/comments"*)
    body='> [!WARNING] > ## Review limit reached > **Next included review available in 39 minutes.** rate limited by coderabbit.ai'
    jq -nc --arg ts "$NOTICE_TS" --arg b "$body" \
      '[{user:{login:"coderabbitai[bot]"},created_at:$ts,updated_at:$ts,body:$b}]'
    exit 0 ;;
esac
exit 1
STUB
chmod +x "$SANDBOX/gh"
export PATH="$SANDBOX:$PATH"

STATE_FILE="$CR_WATCH_STATE_DIR/acme-widget-pr7.ratelimit"
run() { # autoretry -> one poll of the real watcher
  CR_WATCH_AUTORETRY="$1" CR_WATCH_ASSUME_CODERABBIT=1 \
    timeout 20 bash "$WATCHER" --repo acme/widget 7 2>&1
}

# --- A detect-only watcher records the notice and arms nothing -----------------
# CodeRabbit edits its one summary comment in place, so the first sighting of a new
# updated_at must settle across two polls before it is acted on (same trap the
# already-reviewed notice hit; claude-kit#73). Refs #82.
out=$(run 0)
case "$out" in
  *"RATE-LIMITED"*) fail "rate-limited fired on the first sighting, before it settled: $(printf '%s' "$out" | tr '\n' '|')" ;;
  *) pass "rate-limited withheld on the first sighting" ;;
esac
out=$(run 0)
case "$out" in
  *"RATE-LIMITED"*"auto-retry OFF"*) pass "detect-only records the notice, arms nothing" ;;
  *) fail "detect-only run wrong: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac
case "$(cat "$STATE_FILE" 2>/dev/null)" in
  *"	0	0") pass "state records the notice with no retry armed" ;;
  *) fail "unexpected state: $(cat "$STATE_FILE" 2>/dev/null)" ;;
esac
[ -s "$POSTED" ] && fail "detect-only posted a trigger" || pass "and posts nothing"

# --- Re-arming with auto-retry on recovers the lost arming ---------------------
out=$(run 1)
case "$out" in
  *"RETRY RECOVERED"*) pass "a re-armed watcher notices the unarmed notice" ;;
  *) fail "re-arm did not recover: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac
armed_line=$(printf '%s\n' "$out" | grep "RETRY ARMED" | tail -1)
# Two checks, not one: a fixed-phrase match can't tell a delta from nothing.
# This fails if either half goes missing. Refs #82.
if printf '%s' "$armed_line" | grep -qE 'RETRY ARMED — fires (now|in [0-9]+(h([0-9]+m)?|m|s)) \(at '; then
  pass "and says when it will fire, as a delta"
else
  fail "no delta on the armed line: $armed_line"
fi
if printf '%s' "$armed_line" | grep -qE '\(at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\)$'; then
  pass "and keeps the absolute timestamp, in UTC"
else
  fail "no absolute timestamp on the armed line: $armed_line"
fi
# The notice is 90 minutes old and claimed 39, so the window has passed: firing now is
# correct. Arming 39 minutes from the recovery instead would be the bug all over again.
case "$out" in
  *"RE-TRIGGERED"*) pass "an overdue window fires immediately, not 39m from recovery" ;;
  *) fail "overdue window did not fire: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac
grep -q "coderabbitai review" "$POSTED" 2>/dev/null \
  && pass "the trigger really was posted" || fail "no trigger posted"

# --- A spent retry must not re-arm itself off the same stale notice ------------
: > "$POSTED"
out=$(run 1)
case "$out" in
  *"RETRY RECOVERED"*) fail "re-armed off a notice whose retry was already spent" ;;
  *) pass "a spent retry does not recover from the same notice" ;;
esac
[ -s "$POSTED" ] && fail "posted a second trigger for one notice" \
  || pass "and posts no second trigger"

echo
[ "$FAILURES" -eq 0 ] && { echo "all retry recovery tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
