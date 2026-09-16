#!/bin/bash
# PostToolUse(Bash) hook: a gh write that posted a body file from ~/ai-context is told to delete
# the draft, once per file. A draft that landed on GitHub is done here; the run's handoff, spec
# and plan stay. Refs #123. Rung: hook. Skipped: check (nothing periodic sees the posting), rule (ignored).
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0
grep -qE 'gh[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit|review)\b' <<<"$cmd" || exit 0
grep -qE -- '--body-file|(^|[[:space:]])-F([[:space:]]|=)' <<<"$cmd" || exit 0

# A failed post keeps its draft. gh prints HTTP errors on stderr.
err=$(jq -r '.tool_response.stderr // ""' <<<"$in" 2>/dev/null) || err=""
grep -qE 'HTTP [45][0-9]{2}|GraphQL|error' <<<"$err" && exit 0

_lib="$(cd "$(dirname "$0")" && pwd)/lib/gh-command.sh"
[ -f "$_lib" ] || exit 0
. "$_lib"
gh_re='gh\s+(?:issue|pr)\s+(?:create|comment|edit|review)\b'
words=()
while IFS= read -r -d '' w; do words+=("$w"); done < <(printf '%s' "$cmd" | gh_scan words "$gh_re")
cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null) || cwd=""
root="${AI_CONTEXT_ROOT:-$HOME/ai-context}"
state_dir="${DRAFT_POSTED_STATE_DIR:-$HOME/ai-context/state/draft-posted-nudge}"
mkdir -p "$state_dir" 2>/dev/null || exit 0

files=()
for ((i = 3; i < ${#words[@]}; i++)); do
  w=${words[i]} f=""
  case "$w" in
    --body-file|-F) f=${words[i + 1]:-}; i=$((i + 1)) ;;
    --body-file=*|-F=*) f=${w#*=} ;;
    *) continue ;;
  esac
  [ "$f" = "-" ] && continue
  f=$(gh_resolve_path "$cwd" "$(gh_expand_var "$(printf '%s' "$cmd" | gh_scan prefix "$gh_re")" "$f")")
  case "$f" in "$root"/*) ;; *) continue ;; esac
  case "$f" in "$root"/state/*|"$root"/agy-*) continue ;; esac
  case "$(basename "$f")" in handoff.md|spec.md|plan.md) continue ;; esac
  key=$(printf '%s' "$f" | md5sum | cut -c1-16)
  [ -e "$state_dir/$key" ] && continue
  : > "$state_dir/$key" 2>/dev/null
  files+=("$f")
done
[ "${#files[@]}" -gt 0 ] || exit 0

msg="Posted from ${files[*]}. AGENTS.md §Environment: a draft that has landed on GitHub is done here. Delete it now with rm, unless it is the run's handoff, spec or plan."
jq -n --arg ctx "$msg" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
exit 0
