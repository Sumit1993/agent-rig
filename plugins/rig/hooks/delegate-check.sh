#!/bin/bash
# mage:rig/guard/delegate-check
# PreToolUse(Agent) hook: the delegation rule in AGENTS.md is unenforceable as prose —
# by the time you pick a subagent_type you have already decided who, and nothing
# interrupts. This blocks a GENERIC subagent on work that reads as delegable.
# Escape: name agy anywhere in the prompt or description. Considering it is the rule;
# choosing Claude anyway is allowed, silently deciding is not.
# Rung: hook. Skipped: impossible (no deny rule distinguishes delegable intent), check (prompts exist only at spawn time).
set -u
in=$(cat)

_jlib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/json.sh"
[ -f "$_jlib" ] || _jlib="$(cd "$(dirname "$0")" && pwd)/lib/json.sh"
[ -f "$_jlib" ] && . "$_jlib"
type json_get >/dev/null 2>&1 || json_get() { return 1; }

_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

# Codex spawns carry no subagent_type, so "" below is a generic spawn, not a missed field (#141).
type=$(json_get "$in" "" .tool_input.subagent_type) || exit 0
# Match the DESCRIPTION, not the prompt. A long prompt mentions "implement" or "audit"
# somewhere almost every time: replaying real Agent calls, prompt-matching blocked 52% of
# them. The description is the task in the author's own words, so it is the honest signal.
# Codex's spawn_agent sends only tool_input.message, the task in the caller's words (#141).
desc=$(json_get "$in" "" .tool_input.description .tool_input.message) || exit 0
text="$(json_get "$in" "" .tool_input.prompt .tool_input.message) $(json_get "$in" "" .tool_input.description)" || exit 0

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
grep -qiE '^[[:space:]]*(rebase|backfill|migrate|bulk|collect evidence|run the smoke|smoke.?(run|test)|write tests|run the (suite|tests)|triage)\b' <<<"$desc" || exit 0

cat >&2 <<'MSG'
Blocked by the delegation rule (AGENTS.md §Delegation): this reads as bounded, mechanical
work, which belongs on agy (separate abundant quota), not a Claude subagent (scarce pool).

Load the `farm-out` skill and dispatch instead: write the task prompt to a file, then
spawn subagent_type "agy-runner" with the path.

If a Claude subagent is genuinely right — the answer is a ruling, not a procedure — say why
in the prompt or description and re-issue. "Simpler to set up" is not a reason.
mage:rig/guard/delegate-check
MSG
tool=$(json_get "$in" "Agent" .tool_name)
report_guard "rig/guard/delegate-check" "$tool" "$desc"
exit 2
