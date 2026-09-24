#!/bin/bash
# PreToolUse(Agent) hook: three prompt-shape nudges from AGENTS.md §Models and farm-out §Dispatch,
# once per session each. reasoning: Fable or Opus told to echo or show its reasoning
# (declined as reasoning_extraction). verify: a Sonnet prompt with no verification step. planner: a second fable-planner
# inside the prompt-cache hour, where SendMessage to the first is cheaper.
# Refs #123, #79. Rung: hook. Skipped: check (prompts exist only at spawn time), rule (in AGENTS.md, ignored).
set -u
in=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null) || exit 0
case "$tool" in Agent|spawn_agent) ;; *) exit 0 ;; esac
prompt=$(jq -r '.tool_input.prompt // ""' <<<"$in" 2>/dev/null) || exit 0
model=$(jq -r '.tool_input.model // ""' <<<"$in" 2>/dev/null) || model=""
st=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || st=""

session=$(jq -r '.session_id // "nosession"' <<<"$in" 2>/dev/null) || session="nosession"
[ -z "$session" ] || [ "$session" = "null" ] && session="nosession"
state_dir="${AGENT_PROMPT_NUDGE_STATE_DIR:-$HOME/ai-context/state/agent-prompt-nudge}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
once() { [ -e "$state_dir/$session.$1" ] && return 1; : > "$state_dir/$session.$1" 2>/dev/null; }

planner="no"
grep -qE '(^|:)fable-planner$' <<<"$st" && planner="yes"
msgs=()

if { [ "$planner" = "yes" ] || grep -qiE '^(fable|opus)' <<<"$model"; } \
   && grep -qiE 'echo (your |the )?reasoning|show your (reasoning|work|thinking)|think step by step' <<<"$prompt"; then
  once reasoning && msgs+=("AGENTS.md §Models: never ask Opus 5.5 or Fable 5.1 to echo or show its reasoning; both decline it as reasoning_extraction. Cut that line and ask for evidence instead.")
fi

if grep -qiE '^sonnet' <<<"$model" && ! grep -qiE 'verif|confirm|paste (the )?(raw )?output|run .*(test|check)' <<<"$prompt"; then
  once verify && msgs+=("AGENTS.md §Models: Sonnet needs explicit verification steps. Name the commands to run and say to paste their raw output; a Sonnet prompt without them returns claims.")
fi

if [ "$planner" = "yes" ]; then
  stamp="$state_dir/$session.planner-at"
  now=$(date +%s)
  if [ -f "$stamp" ]; then
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    age=$((now - last))
    if [ "$age" -lt 3600 ]; then
      once planner && msgs+=("A fable-planner was spawned $((age / 60)) min ago, inside the prompt-cache hour. SendMessage it the next spec instead; a fresh planner pays for the whole context again (farm-out §Dispatch, #79).")
    fi
  fi
  echo "$now" > "$stamp" 2>/dev/null
fi

[ "${#msgs[@]}" -gt 0 ] || exit 0
jq -n --arg ctx "$(printf '%s ' "${msgs[@]}")" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
exit 0
