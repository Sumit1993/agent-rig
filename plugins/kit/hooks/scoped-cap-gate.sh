#!/bin/bash
# mage:kit/guard/scoped-cap-gate
# PreToolUse(Agent) hook: refuse a spawn on a model whose own weekly cap (Fable) reads critical.
# Reads the /api/oauth/usage cache the status line keeps; no cache or a passed reset allows. Refs #133.
set -u
in=$(cat)
cache="${SCOPED_CAP_USAGE:-$HOME/.claude/metrics/usage-api.json}"

_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

model=$(jq -r '.tool_input.model // ""' <<<"$in" 2>/dev/null) || exit 0
agent=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || exit 0
case "${model,,} ${agent,,}" in
  fable*|*fable-planner*) want=fable ;;
  *) exit 0 ;;
esac
[ -r "$cache" ] || exit 0

row=$(jq -c --arg m "$want" --argjson now "$(date +%s)" '
  [.limits[]? | select(.kind == "weekly_scoped" and ((.scope.model.display_name // "") | ascii_downcase) == $m)
   | select(.severity == "critical")
   | select((.resets_at // "" | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdateiso8601 catch 0) > $now)] | first // empty' "$cache" 2>/dev/null)
[ -n "$row" ] || exit 0

pct=$(jq -r '.percent' <<<"$row"); reset=$(jq -r '.resets_at[0:16]' <<<"$row")
echo "Blocked by kit/guard/scoped-cap-gate: Fable's weekly cap is at ${pct}% (critical) until ${reset}Z. Write the spec or ruling on the session model instead, and say so in the report." >&2
echo "mage:kit/guard/scoped-cap-gate" >&2
report_guard "kit/guard/scoped-cap-gate" "Agent" "${model:-$agent}"
exit 2
