#!/bin/bash
# PostToolUse(Bash) hook: when a `gh pr create` succeeds (PR URL in the output),
# inject a reminder to arm the pr-watch monitor (~/.claude/skills/pr-watch/).
# Silent (exit 0, no output) for every other Bash call.
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
case "$cmd" in
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac
url=$(jq -r '.tool_response | tostring' <<<"$in" 2>/dev/null | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | head -1)
[ -z "$url" ] && exit 0
pr=${url##*/}
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"PR #%s was just raised (%s). Standard practice: arm the pr-watch monitor NOW — invoke the pr-watch skill (Phase 1: seed seen-state, arm Monitor with watch-coderabbit.sh) so CodeRabbit/CI feedback arrives as notifications instead of the user relaying it."}}\n' "$pr" "$url"
