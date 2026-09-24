#!/bin/bash
# SubagentStop hook: refuse subagents returning stall phrasing instead of waiting.
# Checks last_assistant_message first, then falls back to transcript file.
# Codex rejects an exit-0 SubagentStop without JSON on stdout, so passes print {}. Refs #123, #141.
# Rung: hook. Skipped: impossible (subagent output phrasing cannot be restricted by schema), check (the phrasing exists only at subagent stop time).
set -u
in=$(cat)
pass() { echo '{}'; exit 0; }

stop_active=$(jq -r '.stop_hook_active // false' <<<"$in" 2>/dev/null) || pass
[ "$stop_active" = "true" ] && pass

text=$(jq -r '.last_assistant_message // ""' <<<"$in" 2>/dev/null) || pass
if [ -z "$text" ]; then
  tpath=$(jq -r '.agent_transcript_path // .transcript_path // ""' <<<"$in" 2>/dev/null) || pass
  if [ -n "$tpath" ] && [ -f "$tpath" ] && [ -r "$tpath" ]; then
    last_assistant_line=$(grep -E '"type"[[:space:]]*:[[:space:]]*"assistant"' "$tpath" 2>/dev/null | tail -1)
    if [ -n "$last_assistant_line" ]; then
      text=$(jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' <<<"$last_assistant_line" 2>/dev/null) || pass
    fi
  else
    pass
  fi
fi

[ -z "$text" ] && pass

if grep -qiE 'standing by|waiting for the (background|watcher)|will be notified|I.ll wait for' <<<"$text"; then
  cat >&2 <<'MSG'
Blocked by rig/guard/subagent-no-stall: subagent returned stall phrasing.

Read the artifact you are waiting on, wait in the foreground with a deadline, do not return until the evidence resolves.
MSG
  exit 2
fi

pass
