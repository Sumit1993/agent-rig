#!/bin/bash
# Regression suite for limit-log.sh (StopFailure, Notification). Refs #124.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/limit-log.sh"
fails=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
LOG="$T/m/limits.jsonl"

echo '{"session_id":"s1","cwd":"/r","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 Too Many Requests","last_assistant_message":"API Error: Rate limit reached"}' | LIMIT_LOG="$LOG" "$HOOK"
row=$(tail -n1 "$LOG" 2>/dev/null)
[ "$(jq -r .kind <<<"$row")" = "rate_limit" ] && [ "$(jq -r .detail <<<"$row")" = "429 Too Many Requests" ] && [ "$(jq -r .event <<<"$row")" = "StopFailure" ] \
  && echo "PASS: StopFailure row carries error and details" || { echo "FAIL: StopFailure row ($row)"; fails=$((fails+1)); }
jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' <<<"$row" >/dev/null && echo "PASS: row is timestamped" || { echo "FAIL: ts"; fails=$((fails+1)); }

echo '{"session_id":"s1","hook_event_name":"Notification","notification_type":"quota_auto_resume_fired","message":"Continuing after the usage limit reset"}' | LIMIT_LOG="$LOG" "$HOOK"
row=$(tail -n1 "$LOG")
[ "$(jq -r .kind <<<"$row")" = "quota_auto_resume_fired" ] && [ "$(jq -r .detail <<<"$row")" = "Continuing after the usage limit reset" ] \
  && echo "PASS: Notification row carries type and message" || { echo "FAIL: Notification row ($row)"; fails=$((fails+1)); }
[ "$(wc -l < "$LOG")" -eq 2 ] && echo "PASS: appends, never truncates" || { echo "FAIL: line count"; fails=$((fails+1)); }

rc=$(printf 'junk' | LIMIT_LOG="$LOG" "$HOOK" >/dev/null 2>&1; echo $?)
[ "$rc" -eq 0 ] && [ "$(wc -l < "$LOG")" -eq 2 ] && echo "PASS: junk stdin exits 0 and writes nothing" || { echo "FAIL: junk rc=$rc"; fails=$((fails+1)); }
out=$(printf '{}' | LIMIT_LOG="$LOG" "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(wc -l < "$LOG")" -eq 2 ] && echo "PASS: empty payload is silent and unlogged" || { echo "FAIL: empty payload rc=$rc out=$out"; fails=$((fails+1)); }

[ "$fails" -eq 0 ] && echo "all limit-log hook tests passed"; exit "$fails"
