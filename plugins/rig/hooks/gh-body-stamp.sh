#!/bin/bash
# PreToolUse(Bash) hook: gh issue/pr comment/create/edit (+ pr review) must carry the operator-stamp marker in its body.
# gh api and MCP posting tools are not covered.
# Refs #116
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

grep -qE 'gh[[:space:]]+(issue|pr)[[:space:]]' <<<"$cmd" || exit 0
grep -q 'STAMP_GATE=skip' <<<"$cmd" && exit 0

_lib="$(cd "$(dirname "$0")" && pwd)/lib/gh-command.sh"
[ -f "$_lib" ] || exit 0
. "$_lib"

gh_re='gh\s+(?:issue\s+(?:comment|create|edit)|pr\s+(?:comment|create|edit|review))\b'
words=()
while IFS= read -r -d '' w; do words+=("$w"); done < <(printf '%s' "$cmd" | gh_scan words "$gh_re")
[ "${#words[@]}" -ge 3 ] || exit 0
sub=${words[1]} verb=${words[2]}

cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null) || cwd=""
marker="Posted by an agent under the operator's account."
footer='Generated with [Claude Code]'

body=""; found_source=0
for ((i = 3; i < ${#words[@]}; i++)); do
  w=${words[i]} val=""
  case "$w" in
    --body|-b|--body-file|-F) val=${words[i + 1]:-}; i=$((i + 1)) ;;
    --body=*|--body-file=*) val=${w#*=}; w=${w%%=*} ;;
    *) continue ;;
  esac
  case "$w" in
    --body|-b)
      body=$val; found_source=1
      # --body "$(cat <<EOF ...)": the word is the substitution; its heredoc is the body.
      case "$body" in '$('*) body=$(gh_heredoc_body "$body") || body="" ;; esac ;;
    *)
      if [ "$val" = "-" ]; then
        body=$(gh_heredoc_body "$(printf '%s' "$cmd" | gh_scan tail "$gh_re")") && [ -n "$body" ] && found_source=1
      else
        f=$(gh_resolve_path "$cwd" "$(gh_expand_var "$(printf '%s' "$cmd" | gh_scan prefix "$gh_re")" "$val")")
        # A file written earlier in this same call does not exist yet; that is text we cannot see.
        [ -f "$f" ] && [ -r "$f" ] && body=$(cat "$f" 2>/dev/null) && found_source=1
      fi ;;
  esac
done

# No readable body: an --editor session, the web flow, or a file not written yet. Cannot
# see the text, so let it through rather than block blind.
[ "$found_source" = "1" ] || exit 0

[ "${#body}" -ge 40 ] || exit 0

first=$(sed -E 's/^[[:space:]]+//' <<<"$body" | head -c1)
[ "$first" = "@" ] && exit 0

grep -qF "$marker" <<<"$body" && exit 0
if [ "$sub" = "pr" ] && { [ "$verb" = "create" ] || [ "$verb" = "edit" ]; }; then
  grep -qF "$footer" <<<"$body" && exit 0
fi

cat >&2 <<'MSG'
Blocked by rig/guard/gh-body-stamp: agent-posted text carries no marker. Append this line to the body: Posted by an agent under the operator's account. Bypass with STAMP_GATE=skip.
MSG
exit 2
