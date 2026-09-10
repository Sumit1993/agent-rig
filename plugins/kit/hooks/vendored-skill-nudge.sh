#!/bin/bash
# PreToolUse(Skill) hook: inject kit record doctrine when vendored skills load.
# Matches handoff, claude-handoff, to-tickets, research skills.
# Refs #123
set -u
in=$(cat)

skill=$(jq -r '.tool_input.skill // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$skill" ] || exit 0

if grep -qE '(^|:)claude-api$' <<<"$skill"; then
  msg="For a price, a model id or a context window, read only shared/models.md under this skill's base directory; the full skill is about 64K tokens and is for writing SDK code."
elif grep -qE '(^|:)(handoff|claude-handoff|to-tickets|research)$' <<<"$skill"; then
  msg="Records live in GitHub issues, a handoff is a comment on the issue, one umbrella not one issue per unit, never /tmp; where this skill disagrees on where a record lives, AGENTS.md wins."
else
  exit 0
fi
jq -n --arg ctx "$msg" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'

exit 0
