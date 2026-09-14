#!/bin/bash
# PreToolUse(Bash) hook: block gh issue/pr create/comment/edit/review citing scratch paths.
# Reads the gh call's own words and body files, never a --body-file path itself.
# Refs #123
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

grep -qE 'gh[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit|review)\b' <<<"$cmd" || exit 0
grep -q 'SCRATCH_GATE=skip' <<<"$cmd" && exit 0

_lib="$(cd "$(dirname "$0")" && pwd)/lib/gh-command.sh"
[ -f "$_lib" ] || exit 0
. "$_lib"

gh_re='gh\s+(?:issue|pr)\s+(?:create|comment|edit|review)\b'
words=()
while IFS= read -r -d '' w; do words+=("$w"); done < <(printf '%s' "$cmd" | gh_scan words "$gh_re")
[ "${#words[@]}" -ge 3 ] || exit 0

cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null) || cwd=""

body_text=""
for ((i = 3; i < ${#words[@]}; i++)); do
  w=${words[i]} f=""
  case "$w" in
    --body-file|-F) f=${words[i + 1]:-}; i=$((i + 1)) ;;
    --body-file=*) f=${w#*=} ;;
    *) body_text+="$w"$'\n'; continue ;;
  esac
  if [ "$f" = "-" ]; then
    body_text+=$(gh_heredoc_body "$(printf '%s' "$cmd" | gh_scan tail "$gh_re")")$'\n'
    continue
  fi
  f=$(gh_resolve_path "$cwd" "$(gh_expand_var "$(printf '%s' "$cmd" | gh_scan prefix "$gh_re")" "$f")")
  if [ -f "$f" ] && [ -r "$f" ]; then
    body_text+=$(cat "$f" 2>/dev/null || true)$'\n'
  fi
done

if grep -qE 'ai-context|/tmp/' <<<"$body_text"; then
  cat >&2 <<'MSG'
Blocked by rig/guard/gh-body-no-scratch: body text references scratch paths (ai-context or /tmp/).

A record copies its evidence in (AGENTS.md §Issues are the record). Scratch paths are wiped or live on another machine.

If this reference is intentional, bypass with SCRATCH_GATE=skip.
MSG
  exit 2
fi

exit 0
