#!/bin/bash
# PreToolUse(Bash) hook: nudge on third gh issue create to fold into an umbrella.
# State file tracks count per session; only count 3 outputs additionalContext.
# Refs #123
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

grep -qE 'gh[[:space:]]+issue[[:space:]]+create\b' <<<"$cmd" || exit 0

session=$(jq -r '.session_id // "nosession"' <<<"$in" 2>/dev/null) || session="nosession"
[ -z "$session" ] || [ "$session" = "null" ] && session="nosession"

state_dir="${ISSUE_NUDGE_STATE_DIR:-$HOME/ai-context/state/issue-create-nudge}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
flag="$state_dir/$session"

count=0
if [ -f "$flag" ]; then
  count=$(cat "$flag" 2>/dev/null || echo 0)
  case "$count" in ''|*[!0-9]*) count=0;; esac
fi
count=$((count + 1))
echo "$count" > "$flag" 2>/dev/null || exit 0

if [ "$count" -eq 3 ]; then
  msg="Third gh issue create this session; AGENTS.md §Issues are the record: one umbrella issue per unit of related work, not one issue per item; fold these into an umbrella unless each is its own unit."
  jq -n --arg ctx "$msg" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": $ctx
    }
  }'
fi

exit 0
