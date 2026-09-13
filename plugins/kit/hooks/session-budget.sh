#!/bin/bash
# SessionStart hook: one line of budget the operator used to type by hand: the 5h and 7d
# account percent from the statusline trace, and agy's quota state per group. Refs #123.
# On resume or fork, the resume-cost fields Claude Code sends (v2.1.251+) become one more sentence.
set -u
in=$(cat)
log="${BUDGET_USAGE_LOG:-$HOME/.claude/metrics/usage.jsonl}"
quota="${BUDGET_QUOTA_SH:-$(cd "$(dirname "$0")/.." && pwd)/skills/farm-out/agy-quota.sh}"

acct="no trace yet"
if [ -r "$log" ]; then
  row=$(tail -n 1 "$log" 2>/dev/null)
  # The trace row is written at the last statusline redraw; a window whose resets_at has passed since reads 0.
  now=$(date +%s)
  five=$(jq -r --argjson now "$now" '.five_hour | if . == null then empty elif (.resets_at // 0) > 0 and .resets_at <= $now then 0 else .used_percentage end' <<<"$row" 2>/dev/null)
  week=$(jq -r --argjson now "$now" '.seven_day | if . == null then empty elif (.resets_at // 0) > 0 and .resets_at <= $now then 0 else .used_percentage end' <<<"$row" 2>/dev/null)
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

policy="Per-model weekly caps (Fable) are not in the statusline payload; ask the operator for /usage before a Fable dispatch. Past 60% on the 5h window: Sonnet subagents only, no research fan-out, no planner respawn. A dry agy group means the Sonnet handler does the task itself from the prompt file and says so."
resume=""
src=$(jq -r '.source // empty' <<<"$in" 2>/dev/null)
gap=$(jq -r '.seconds_since_last_response // empty' <<<"$in" 2>/dev/null)
if [ -n "$gap" ] && { [ "$src" = "resume" ] || [ "$src" = "fork" ]; }; then
  ctx_tok=$(jq -r '.context_tokens // "?"' <<<"$in" 2>/dev/null)
  cold=$(jq -r '.prompt_cache_likely_expired // false' <<<"$in" 2>/dev/null)
  [ "$cold" = "true" ] && cache="prompt cache likely expired, the first request rebuilds it" || cache="prompt cache likely warm"
  resume=" Resumed after $((gap / 60))m: ${ctx_tok} context tokens re-sent, ${cache}."
fi
msg="Budget: ${acct}. agy gemini: ${g}. agy claude-gpt: ${c}.${resume} ${policy}"
jq -n --arg ctx "$msg" '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
exit 0
