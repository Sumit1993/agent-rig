#!/bin/bash
# Regression suite for budget-nudge.sh (PostToolUse). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/budget-nudge.sh"
fails=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
future=$(( $(date +%s) + 3600 ))
row() { printf '{"five_hour":{"used_percentage":%s,"resets_at":%s}}\n' "$1" "$2" >> "$T/usage.jsonl"; }
run() { echo "{\"session_id\":\"${1:-s1}\"}" | BUDGET_USAGE_LOG="$T/usage.jsonl" BUDGET_NUDGE_STATE="$T/state" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1 ($out)"; fails=$((fails+1)); fi; }

row 70 "$future"; out=$(run)
check "below 80 is silent" '[ -z "$out" ]'
row 82 "$future"; out=$(run)
check "crossing 80 nudges to wind down" 'grep -q "at 82%.*Start winding down" <<<"$out"'
row 85 "$future"; out=$(run)
check "80 nudges once per window" '[ -z "$out" ]'
out=$(run s2)
check "another session gets its own 80 nudge" 'grep -q "Start winding down" <<<"$out"'
row 91 "$future"; out=$(run)
check "crossing 90 nudges to hand off" 'grep -q "at 91%.*Stop starting work.*handoff comment" <<<"$out"'
out=$(run)
check "90 nudges once per window" '[ -z "$out" ]'
row 83 "$(( future + 18000 ))"; out=$(run)
check "a new window nudges again at 80" 'grep -q "Start winding down" <<<"$out"'
row 95 1; out=$(run s3)
check "a window whose resets_at passed is silent" '[ -z "$out" ]'

rc=$(printf 'junk' | BUDGET_USAGE_LOG="$T/usage.jsonl" BUDGET_NUDGE_STATE="$T/state" "$HOOK" >/dev/null 2>&1; echo $?)
check "junk stdin exits 0" '[ "$rc" -eq 0 ]'

[ "$fails" -eq 0 ] && echo "all budget-nudge hook tests passed"; exit "$fails"
