#!/bin/bash
# SessionStart hook: one line of budget the operator used to type by hand: the 5h and 7d
# account percent from the statusline trace, and agy's quota state per group. Refs #123
set -u
in=$(cat)
log="${BUDGET_USAGE_LOG:-$HOME/.claude/metrics/usage.jsonl}"
quota="${BUDGET_QUOTA_SH:-$(cd "$(dirname "$0")/.." && pwd)/skills/agy-delegate/agy-quota.sh}"

acct="no trace yet"
if [ -r "$log" ]; then
  row=$(tail -n 1 "$log" 2>/dev/null)
  five=$(jq -r '.five_hour.used_percentage // empty' <<<"$row" 2>/dev/null)
  week=$(jq -r '.seven_day.used_percentage // empty' <<<"$row" 2>/dev/null)
  ts=$(jq -r '.ts // empty' <<<"$row" 2>/dev/null)
  if [ -n "$five" ]; then
    age=""
    if [ -n "$ts" ]; then
      secs=$(( $(date +%s) - $(date -d "$ts" +%s 2>/dev/null || date +%s) )); age=", read $((secs / 60))m ago"
    fi
    acct="5h window ${five%.*}%, 7d ${week%.*}%${age}"
  fi
fi
g=$( [ -x "$quota" ] && "$quota" check gemini-3.8-flash-high 2>/dev/null | head -1 || echo "unknown")
c=$( [ -x "$quota" ] && "$quota" check claude-opus-4.6 2>/dev/null | head -1 || echo "unknown")

policy="Past 60% on the 5h window: Sonnet subagents only, no research fan-out, no planner respawn. A dry agy group means the Sonnet handler does the task itself from the prompt file and says so."
msg="Budget: ${acct}. agy gemini: ${g}. agy claude-gpt: ${c}. ${policy}"
jq -n --arg ctx "$msg" '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
exit 0
