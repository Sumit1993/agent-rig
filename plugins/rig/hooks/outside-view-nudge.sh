#!/bin/bash
# PreToolUse(AskUserQuestion|EnterPlanMode|Agent) hook: at the moment an agent admits it is
# unsure, remind it to get an outside view first. Fires on the 1st occurrence per session,
# then every 3rd, so it stays a nudge. Refs #123.
# Rung: hook. Skipped: impossible (uncertainty tools cannot be blocked outright), check (the signal exists only at call time).
set -u
in=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null) || exit 0
case "$tool" in
  AskUserQuestion|EnterPlanMode) ;;
  # Codex's Agent matcher aliases spawn_agent, but the payload says spawn_agent (#141).
  Agent|spawn_agent)
    # Claude counts only fable-planner; Codex spawns have no subagent_type, so every one counts (#141).
    has_type=$(jq -r 'if (.tool_input | has("subagent_type")) then "yes" else "no" end' <<<"$in" 2>/dev/null) || exit 0
    if [ "$has_type" = "yes" ]; then
      st=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || exit 0
      grep -qE '(^|:)fable-planner$' <<<"$st" || exit 0
    fi ;;
  *) exit 0 ;;
esac

session=$(jq -r '.session_id // "nosession"' <<<"$in" 2>/dev/null) || session="nosession"
[ -z "$session" ] || [ "$session" = "null" ] && session="nosession"
state_dir="${OUTSIDE_VIEW_STATE_DIR:-$HOME/ai-context/state/outside-view-nudge}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
flag="$state_dir/$session"
count=0
[ -f "$flag" ] && { count=$(cat "$flag" 2>/dev/null || echo 0); case "$count" in ''|*[!0-9]*) count=0;; esac; }
count=$((count + 1))
echo "$count" > "$flag" 2>/dev/null || exit 0
[ $((count % 3)) -eq 1 ] || exit 0

msg="Before you ask, plan or rule: does this question have an outside answer (a comparable tool, a primary doc, a paper)? If it does, search and read it first; then name what you read, or say none was found (AGENTS.md §Stance)."
jq -n --arg ctx "$msg" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
exit 0
