#!/bin/bash
# PreToolUse(Agent) hook: routing doctrine — never Haiku for real work.
set -u
in=$(cat)
model=$(jq -r '.tool_input.model // ""' <<<"$in" 2>/dev/null) || exit 0
[ "$model" = "haiku" ] || exit 0
echo "Blocked by routing doctrine (~/.claude/CLAUDE.md): never use Haiku. Pick sonnet or above." >&2
exit 2
