#!/bin/bash
# PreToolUse(Skill) hook: inject kit record doctrine when vendored skills load.
# Matches handoff, claude-handoff, to-tickets, research skills.
# Refs #123
set -u
in=$(cat)

skill=$(jq -r '.tool_input.skill // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$skill" ] || exit 0

grep -qE '(^|:)(handoff|claude-handoff|to-tickets|research)$' <<<"$skill" || exit 0

msg="Records live in GitHub issues, a handoff is a comment on the issue, one umbrella not one issue per unit, never /tmp; where this skill disagrees on where a record lives, AGENTS.md wins."
jq -n --arg ctx "$msg" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'

exit 0
