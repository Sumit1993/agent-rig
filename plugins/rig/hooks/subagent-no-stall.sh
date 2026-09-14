#!/bin/bash
# SubagentStop hook: refuse subagents returning stall phrasing instead of waiting.
# Checks last_assistant_message first, then falls back to transcript file.
# Refs #123
set -u
in=$(cat)

stop_active=$(jq -r '.stop_hook_active // false' <<<"$in" 2>/dev/null) || exit 0
[ "$stop_active" = "true" ] && exit 0

text=$(jq -r '.last_assistant_message // ""' <<<"$in" 2>/dev/null) || exit 0
if [ -z "$text" ]; then
  tpath=$(jq -r '.agent_transcript_path // .transcript_path // ""' <<<"$in" 2>/dev/null) || exit 0
  if [ -n "$tpath" ] && [ -f "$tpath" ] && [ -r "$tpath" ]; then
    last_assistant_line=$(grep -E '"type"[[:space:]]*:[[:space:]]*"assistant"' "$tpath" 2>/dev/null | tail -1)
    if [ -n "$last_assistant_line" ]; then
      text=$(jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' <<<"$last_assistant_line" 2>/dev/null) || exit 0
    fi
  else
    exit 0
  fi
fi

[ -z "$text" ] && exit 0

if grep -qiE 'standing by|waiting for the (background|watcher)|will be notified|I.ll wait for' <<<"$text"; then
  cat >&2 <<'MSG'
Blocked by rig/guard/subagent-no-stall: subagent returned stall phrasing.

Read the artifact you are waiting on, wait in the foreground with a deadline, do not return until the evidence resolves.
MSG
  exit 2
fi

exit 0
