#!/bin/bash
# StopFailure(rate_limit|overloaded) and Notification(quota_auto_resume_*): one JSON line per
# event in ~/.claude/metrics/limits.jsonl, so a limit hit has a timestamp the transcripts
# lack. Refs #124. Output and exit code are ignored by Claude Code on both events.
set -u
in=$(cat)
log="${LIMIT_LOG:-$HOME/.claude/metrics/limits.jsonl}"
row=$(jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
  ts: $ts,
  session_id: (.session_id // ""),
  cwd: (.cwd // ""),
  event: (.hook_event_name // ""),
  kind: (.error // .notification_type // ""),
  detail: ((.error_details // .message // .last_assistant_message // "") | tostring | .[0:200])
}' <<<"$in" 2>/dev/null) || exit 0
[ -n "$row" ] && [ "$(jq -r .kind <<<"$row")" != "" ] || exit 0
mkdir -p "$(dirname "$log")" 2>/dev/null && printf '%s\n' "$row" >> "$log" 2>/dev/null
exit 0
