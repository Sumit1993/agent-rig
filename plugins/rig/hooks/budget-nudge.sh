#!/bin/bash
# PostToolUse hook: when the 5h window crosses 80% and again at 90%, tell the session to wind down.
# Reads the statusline trace, so a session with no statusline redraw sees nothing. Once per level,
# per session, per window (keyed by resets_at). Refs #123.
# Rung: hook. Skipped: impossible (no harness mechanism caps a session by usage percent), check (the 5h window evolves during the session).
set -u
in=$(cat)
log="${BUDGET_USAGE_LOG:-$HOME/.claude/metrics/usage.jsonl}"
state_dir="${BUDGET_NUDGE_STATE:-$HOME/.claude/metrics/budget-nudge}"
[ -r "$log" ] || exit 0
session=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null)
[ -n "$session" ] || exit 0

row=$(tail -n 1 "$log" 2>/dev/null)
now=$(date +%s)
read -r pct resets < <(jq -r '.five_hour | select(. != null) | "\(.used_percentage | floor) \(.resets_at // 0)"' <<<"$row" 2>/dev/null) || exit 0
[ -n "${pct:-}" ] && [ "$resets" -gt "$now" ] || exit 0

level=0
[ "$pct" -ge 80 ] && level=80
[ "$pct" -ge 90 ] && level=90
[ "$level" -eq 0 ] && exit 0

mkdir -p "$state_dir"
state="$state_dir/$session"
last=$(cat "$state" 2>/dev/null)
[ "${last%%:*}" = "$resets" ] && [ "${last##*:}" -ge "$level" ] && exit 0
echo "$resets:$level" > "$state"

at=$(date -u -d "@$resets" +%H:%MZ)
if [ "$level" -eq 90 ]; then
  msg="Budget: 5h window at ${pct}%, resets ${at}. Stop starting work. Now: push local commits to their draft PRs, then post the handoff comment on each umbrella issue with what landed, what is open, and the exact next commands. Tell live lanes to commit and report."
else
  msg="Budget: 5h window at ${pct}%, resets ${at}. Start winding down: no new lanes or research fan-out, let live lanes finish, and bring each umbrella issue up to date with the latest evidence so a handoff at 90% is one comment."
fi
jq -n --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
