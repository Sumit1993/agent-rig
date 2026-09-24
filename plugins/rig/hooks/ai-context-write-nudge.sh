#!/bin/bash
# PreToolUse(Write|Edit|NotebookEdit) hook: two nudges on writes under ~/ai-context, once per session each.
# layout: a path off <repo>/<issue>-<slug>/ gets the suggested shape (a suggestion, never a block).
# ruling: a file named like a ruling, spec or handoff is reminded that the decision goes on the issue.
# Refs #123. Rung: hook. Skipped: check (no CI sees ~/ai-context), rule (a layout rule nobody reads at write time).
set -u
in=$(cat)
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in" 2>/dev/null) || exit 0
root="${AI_CONTEXT_ROOT:-$HOME/ai-context}"
case "$path" in "$root"/*) ;; *) exit 0 ;; esac
rel=${path#"$root"/}

session=$(jq -r '.session_id // "nosession"' <<<"$in" 2>/dev/null) || session="nosession"
[ -z "$session" ] || [ "$session" = "null" ] && session="nosession"
state_dir="${AI_CONTEXT_NUDGE_STATE_DIR:-$HOME/ai-context/state/ai-context-write-nudge}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
once() { [ -e "$state_dir/$session.$1" ] && return 1; : > "$state_dir/$session.$1" 2>/dev/null; }

msgs=()
case "$rel" in
  state/*|telemetry/*|agy-*|backups/*|vendor/*) ;;
  *)
    if ! grep -qE '^[A-Za-z0-9_.-]+/[0-9]+-[A-Za-z0-9_.-]+/' <<<"$rel"; then
      once layout && msgs+=("Suggested ~/ai-context layout, a nudge not a rule: <repo>/<issue-or-pr>-<slug>/ with handoff.md, spec.md, plan.md, drafts/, raw/. The issue number is what lets a sweep delete the directory once the issue closes. You are writing $rel.")
    fi ;;
esac
base=$(basename "$path")
if grep -qiE '(ruling|adr|decision|spec|handoff|resume|handback)' <<<"$base"; then
  once ruling && msgs+=("A ruling or handoff that ends in ~/ai-context did not happen (AGENTS.md §Issues are the record). Before the session ends, the decision line and the delta go on the issue; this file stays here as the working record. A draft posted to GitHub gets deleted.")
fi
[ "${#msgs[@]}" -gt 0 ] || exit 0
jq -n --arg ctx "$(printf '%s ' "${msgs[@]}")" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
exit 0
