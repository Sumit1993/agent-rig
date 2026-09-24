#!/bin/bash
# PreToolUse(Bash) hook: nudges at the moment of a gh write, once per session per kind.
# handoff: a body shaped like a handoff, or over 40 lines, belongs in ~/ai-context and the
# issue gets the delta. cite: a bare #N with no title. nondraft: gh pr create without --draft.
# Refs #123. Rung: hook. Skipped: check (the body exists only at call time), rule (in AGENTS.md, ignored).
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0
grep -qE 'gh[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit)\b' <<<"$cmd" || exit 0

session=$(jq -r '.session_id // "nosession"' <<<"$in" 2>/dev/null) || session="nosession"
[ -z "$session" ] || [ "$session" = "null" ] && session="nosession"
state_dir="${GH_WRITE_NUDGE_STATE_DIR:-$HOME/ai-context/state/gh-write-nudge}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
once() { [ -e "$state_dir/$session.$1" ] && return 1; : > "$state_dir/$session.$1" 2>/dev/null; }

_lib="$(cd "$(dirname "$0")" && pwd)/lib/gh-command.sh"
[ -f "$_lib" ] || exit 0
. "$_lib"

gh_re='gh\s+(?:issue|pr)\s+(?:create|comment|edit)\b'
words=()
while IFS= read -r -d '' w; do words+=("$w"); done < <(printf '%s' "$cmd" | gh_scan words "$gh_re")
[ "${#words[@]}" -ge 3 ] || exit 0
cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null) || cwd=""

body_text="" draft="no"
[ "${words[1]}" = "pr" ] && [ "${words[2]}" = "create" ] && draft="check"
for ((i = 3; i < ${#words[@]}; i++)); do
  w=${words[i]} f=""
  case "$w" in
    --draft|-d) draft="yes"; continue ;;
    --body-file|-F) f=${words[i + 1]:-}; i=$((i + 1)) ;;
    --body-file=*) f=${w#*=} ;;
    --body|-b) body_text+="${words[i + 1]:-}"$'\n'; i=$((i + 1)); continue ;;
    --body=*) body_text+="${w#*=}"$'\n'; continue ;;
    *) continue ;;
  esac
  if [ "$f" = "-" ]; then
    body_text+=$(gh_heredoc_body "$(printf '%s' "$cmd" | gh_scan tail "$gh_re")")$'\n'
    continue
  fi
  f=$(gh_resolve_path "$cwd" "$(gh_expand_var "$(printf '%s' "$cmd" | gh_scan prefix "$gh_re")" "$f")")
  [ -f "$f" ] && [ -r "$f" ] && body_text+=$(cat "$f" 2>/dev/null || true)$'\n'
done

msgs=()
lines=$(printf '%s' "$body_text" | grep -c '' || true)
if grep -qiE '^#+ *(handoff|resume|handback|state at|lane table|work queue)|decisions? owed|resume handoff|lane (spec|table)' <<<"$body_text" \
   || [ "$lines" -gt 40 ]; then
  once handoff && msgs+=("This body reads as a handoff, or runs $lines lines. AGENTS.md §Issues are the record: the issue gets the decision, its Done when and one line on what changed; handoffs, state tables and lane specs go to ~/ai-context/<repo>/<issue>-<slug>/handoff.md. Post if this is the decision.")
fi
if [ -n "$body_text" ] && printf '%s' "$body_text" | grep -qP '(?<![&\w])#\d+\b(?! - )'; then
  once cite && msgs+=("A bare #N in this body. AGENTS.md §Writing: cite an issue or PR with its title, \`#N - title\`, so the reader does not have to open it.")
fi
if [ "$draft" = "check" ]; then
  once nondraft && msgs+=("gh pr create without --draft spends this hour's CodeRabbit slot at creation (AGENTS.md §Reviewers). Add --draft unless the PR is ready for judgement now.")
fi
[ "${#msgs[@]}" -gt 0 ] || exit 0
jq -n --arg ctx "$(printf '%s ' "${msgs[@]}")" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
exit 0
