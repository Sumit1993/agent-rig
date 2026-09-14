#!/bin/bash
# mage:rig/guard/delegate-check
# PreToolUse(Agent) hook: the delegation rule in AGENTS.md is unenforceable as prose —
# by the time you pick a subagent_type you have already decided who, and nothing
# interrupts. This blocks a GENERIC subagent on work that reads as delegable.
# Escape: name agy anywhere in the prompt or description. Considering it is the rule;
# choosing Claude anyway is allowed, silently deciding is not.
set -u
in=$(cat)

_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

type=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || exit 0
# Match the DESCRIPTION, not the prompt. A long prompt mentions "implement" or "audit"
# somewhere almost every time: replaying real Agent calls, prompt-matching blocked 52% of
# them. The description is the task in the author's own words, so it is the honest signal.
desc=$(jq -r '.tool_input.description // ""' <<<"$in" 2>/dev/null) || exit 0
text=$(jq -r '[.tool_input.prompt // "", .tool_input.description // ""] | join(" ")' <<<"$in" 2>/dev/null) || exit 0

# Purpose-built agents already encode their routing; only the catch-alls are in scope.
case "$type" in
  ""|general-purpose|claude|Explore|fork) ;;
  *) exit 0 ;;
esac

# Already routed, or the reason is stated. Either way the decision was made consciously.
grep -qiE 'agy|antigravity' <<<"$text" && exit 0

# Leading verb only, and only verbs that name mechanical execution. Deliberately omits
# verify/validate/research/audit: those read as judgment as often as not, and a blocking
# hook wants precision over recall — a false block costs more than a missed nudge.
grep -qiE '^[[:space:]]*(implement|rebase|backfill|migrate|scaffold|port|bulk|collect evidence|run the smoke|smoke.?(run|test))\b' <<<"$desc" || exit 0

cat >&2 <<'MSG'
Blocked by the delegation rule (AGENTS.md §Delegation): this reads as bounded, mechanical
work, which belongs on agy (separate abundant quota), not a Claude subagent (scarce pool).

Load the `farm-out` skill and dispatch instead: write the task prompt to a file, then
spawn subagent_type "agy-runner" with the path.

If a Claude subagent is genuinely right — the answer is a ruling, not a procedure — say why
in the prompt or description and re-issue. "Simpler to set up" is not a reason.
mage:rig/guard/delegate-check
MSG
tool=$(jq -r '.tool_name // "Agent"' <<<"$in" 2>/dev/null)
report_guard "rig/guard/delegate-check" "$tool" "$desc"
exit 2
