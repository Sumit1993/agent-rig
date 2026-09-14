#!/bin/bash
# Regression suite for outside-view-nudge.sh (PreToolUse AskUserQuestion|EnterPlanMode|Agent). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/outside-view-nudge.sh"
fails=0
export OUTSIDE_VIEW_STATE_DIR=$(mktemp -d)
trap 'rm -rf "$OUTSIDE_VIEW_STATE_DIR"' EXIT

got=$(printf 'not json' | "$HOOK" >/dev/null 2>&1; echo $?)
case "$got" in 0|2) echo "PASS: junk stdin exits $got" ;; *) echo "FAIL: junk stdin rc=$got"; fails=$((fails+1)) ;; esac

run() { jq -n --arg s "$1" --arg t "$2" --arg st "${3:-}" '{"session_id":$s,"tool_name":$t,"tool_input":{"subagent_type":$st}}' | "$HOOK"; }
check() { # name, expect_output(yes/no), output, rc
  if [ "$4" -ne 0 ]; then echo "FAIL: $1 rc=$4"; fails=$((fails+1)); return; fi
  if [ "$2" = yes ] && grep -q "outside answer" <<<"$3"; then echo "PASS: $1"
  elif [ "$2" = no ] && [ -z "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1 (output: ${3:0:60})"; fails=$((fails+1)); fi
}
out=$(run s1 AskUserQuestion); check "1st AskUserQuestion fires" yes "$out" $?
out=$(run s1 EnterPlanMode); check "2nd occurrence silent" no "$out" $?
out=$(run s1 AskUserQuestion); check "3rd occurrence silent" no "$out" $?
out=$(run s1 AskUserQuestion); check "4th occurrence fires again" yes "$out" $?
out=$(run s2 Agent rig:fable-planner); check "fable-planner spawn fires in a new session" yes "$out" $?
out=$(run s3 Agent general-purpose); check "other agent spawn silent" no "$out" $?
out=$(run s4 Bash); check "unrelated tool silent" no "$out" $?
out=$(jq -n '{"session_id":"s5","tool_name":"AskUserQuestion"}' | "$HOOK"); check "fires without tool_input" yes "$out" $?
out=$(run s6 AskUserQuestion); jq -e '.hookSpecificOutput.hookEventName=="PreToolUse"' <<<"$out" >/dev/null 2>&1 && echo "PASS: output is the PreToolUse JSON shape" || { echo "FAIL: JSON shape"; fails=$((fails+1)); }

if [ "$fails" -eq 0 ]; then echo "all outside-view-nudge hook tests passed"; exit 0; fi
echo "$fails outside-view-nudge hook tests FAILED"; exit 1
