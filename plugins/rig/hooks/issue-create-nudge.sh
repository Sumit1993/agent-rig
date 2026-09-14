#!/bin/bash
# PreToolUse(Bash) hook: nudge on a gh issue create with no issue search earlier in the session,
# and on the third create, to fold into an umbrella. State files per session. Refs #123, #120.
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

session=$(jq -r '.session_id // "nosession"' <<<"$in" 2>/dev/null) || session="nosession"
[ -z "$session" ] || [ "$session" = "null" ] && session="nosession"

state_dir="${ISSUE_NUDGE_STATE_DIR:-$HOME/ai-context/state/issue-create-nudge}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
flag="$state_dir/$session"

if grep -qE 'gh[[:space:]]+search[[:space:]]+issues|gh[[:space:]]+issue[[:space:]]+list.*(--search|-S)' <<<"$cmd"; then
  touch "$flag.searched" 2>/dev/null
fi
_lib="$(cd "$(dirname "$0")" && pwd)/lib/gh-command.sh"
[ -f "$_lib" ] || exit 0
. "$_lib"
printf '%s' "$cmd" | gh_scan prefix 'gh\s+issue\s+create\b' >/dev/null || exit 0

count=0
if [ -f "$flag" ]; then
  count=$(cat "$flag" 2>/dev/null || echo 0)
  case "$count" in ''|*[!0-9]*) count=0;; esac
fi
count=$((count + 1))
echo "$count" > "$flag" 2>/dev/null || exit 0

msg=""
if [ ! -f "$flag.searched" ] && [ ! -f "$flag.nudged" ]; then
  touch "$flag.nudged" 2>/dev/null
  msg="No issue search ran this session before this gh issue create. Load triage: search open and closed issues first, then comment on a match instead of filing."
fi
if [ "$count" -eq 3 ]; then
  msg="${msg:+$msg }Third gh issue create this session; AGENTS.md §Issues are the record: one umbrella issue per unit of related work, not one issue per item; fold these into an umbrella unless each is its own unit."
fi
if [ -n "$msg" ]; then
  jq -n --arg ctx "$msg" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": $ctx
    }
  }'
fi

exit 0
