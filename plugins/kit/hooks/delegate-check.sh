#!/bin/bash
# PreToolUse(Agent) hook: the delegation rule in AGENTS.md is unenforceable as prose —
# by the time you pick a subagent_type you have already decided who, and nothing
# interrupts. This blocks a GENERIC subagent on work that reads as delegable.
# Escape: name agy anywhere in the prompt or description. Considering it is the rule;
# choosing Claude anyway is allowed, silently deciding is not.
set -u
in=$(cat)

type=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || exit 0
text=$(jq -r '[.tool_input.prompt // "", .tool_input.description // ""] | join(" ")' <<<"$in" 2>/dev/null) || exit 0

# Purpose-built agents already encode their routing; only the catch-alls are in scope.
case "$type" in
  ""|general-purpose|claude|Explore|fork) ;;
  *) exit 0 ;;
esac

# Already routed, or the reason is stated. Either way the decision was made consciously.
grep -qiE 'agy|antigravity' <<<"$text" && exit 0

grep -qiE 'implement|to spec|rebase|collect|evidence|triage|smoke.?(run|test)|repetitive|per-item|bulk|inventor|sweep|backfill|migrat|audit|research' <<<"$text" || exit 0

cat >&2 <<'MSG'
Blocked by the delegation rule (AGENTS.md §Delegation): this reads as bounded, mechanical
work, which belongs on agy (separate abundant quota), not a Claude subagent (scarce pool).

Load the `agy-delegate` skill and dispatch instead: write the task prompt to a file, then
spawn subagent_type "agy-runner" with the path.

If a Claude subagent is genuinely right — the answer is a ruling, not a procedure — say why
in the prompt or description and re-issue. "Simpler to set up" is not a reason.
MSG
exit 2
