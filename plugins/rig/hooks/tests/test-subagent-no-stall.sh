#!/bin/bash
# Regression suite for subagent-no-stall.sh (SubagentStop). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/subagent-no-stall.sh"
fails=0
TMPDIR_TEST=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

check_json() { # name want_rc json_str
  local name=$1 want=$2 payload=$3 got
  printf '%s' "$payload" | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got)"; fails=$((fails + 1))
  fi
}

got=$(printf 'not json' | "$HOOK" >/dev/null 2>&1; echo $?)
case "$got" in
  0|2) echo "PASS: junk stdin exits $got" ;;
  *) echo "FAIL: junk stdin rc=$got"; fails=$((fails + 1)) ;;
esac

STALL_TRANSCRIPT="$TMPDIR_TEST/stall.jsonl"
cat > "$STALL_TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Analyzing task"},{"type":"text","text":"Starting run"}]}}
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Waiting for output"},{"type":"text","text":"Standing by for the watcher"}]}}
JSONL

CLEAN_TRANSCRIPT="$TMPDIR_TEST/clean.jsonl"
cat > "$CLEAN_TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Analyzing task"},{"type":"text","text":"Starting run"}]}}
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Completed"},{"type":"text","text":"Verified report: all tests pass"}]}}
JSONL

check_json "last_assistant_message standing by for the watcher blocks" 2 \
  '{"last_assistant_message":"Standing by for the watcher"}'

check_json "last_assistant_message I will wait for agy run blocks" 2 \
  '{"last_assistant_message":"I'\''ll wait for the agy run"}'

check_json "verified report passes" 0 \
  '{"last_assistant_message":"Verified report: 12 tests passed, rc=0"}'

check_json "stop_hook_active true with stall text passes" 0 \
  '{"stop_hook_active":true,"last_assistant_message":"Standing by for the watcher"}'

check_json "no last_assistant_message, transcript last line stalls blocks" 2 \
  "$(jq -n --arg p "$STALL_TRANSCRIPT" '{"agent_transcript_path": $p}')"

check_json "transcript last line clean passes" 0 \
  "$(jq -n --arg p "$CLEAN_TRANSCRIPT" '{"agent_transcript_path": $p}')"

[ "$fails" -eq 0 ] && echo && echo "all subagent-no-stall hook tests passed"
exit "$fails"
