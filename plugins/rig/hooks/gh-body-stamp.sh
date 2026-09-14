#!/bin/bash
# PreToolUse(Bash) hook: gh issue/pr comment/create/edit (+ pr review) must carry the operator-stamp marker in its body.
# gh api and MCP posting tools are not covered.
# Refs #116
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

issue_pat='gh[[:space:]]+issue[[:space:]]+(comment|create|edit)\b'
pr_pat='gh[[:space:]]+pr[[:space:]]+(comment|create|edit|review)\b'
if [[ "$cmd" =~ $issue_pat ]]; then
  verb="${BASH_REMATCH[1]}"; sub="issue"
elif [[ "$cmd" =~ $pr_pat ]]; then
  verb="${BASH_REMATCH[1]}"; sub="pr"
else
  exit 0
fi

grep -q 'STAMP_GATE=skip' <<<"$cmd" && exit 0

_lib="$(cd "$(dirname "$0")" && pwd)/lib/gh-command.sh"
[ -f "$_lib" ] || exit 0
. "$_lib"

cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null) || cwd=""
marker="Posted by an agent under the operator's account."
footer='Generated with [Claude Code]'

# A marker anywhere in the call counts: a body file written earlier in the same call
# does not exist yet when this runs, so only the command text can show it.
norm=$(gh_normalize_quotes "$cmd")
grep -qF "$marker" <<<"$norm" && exit 0
footer_ok() { [ "$sub" = "pr" ] && { [ "$verb" = "create" ] || [ "$verb" = "edit" ]; }; }
footer_ok && grep -qF "$footer" <<<"$norm" && exit 0

cmd=$(gh_from_invocation "$cmd" "gh[[:space:]]+$sub[[:space:]]+$verb") || exit 0
resolve_path() { gh_resolve_path "$cwd" "$(gh_expand_var "$norm" "$1")"; }

# The body from a heredoc passed as `--body-file -`: find its opening `<<[-]TAG`
# and return the lines up to the line that is just TAG.
heredoc_body() {
  local text="$1" open tag
  open=$(grep -oE "<<-?[\"']?[A-Za-z_][A-Za-z0-9_]*[\"']?" <<<"$text" | head -1)
  [ -n "$open" ] || return 1
  tag=$(sed -E "s/^<<-?[\"']?//; s/[\"']?\$//" <<<"$open")
  awk -v tag="$tag" '
    found && $0 ~ ("^[[:space:]]*" tag "[[:space:]]*$") { exit }
    found { print; next }
    !found && $0 ~ ("<<-?[\"'"'"']?" tag) { found=1 }
  ' <<<"$text"
}

body=""; found_source=0

body_pat="(--body)[[:space:]=]+(\"([^\"]*)\"|'([^']*)'|([^[:space:]]+))"
short_pat="(^|[[:space:]])-b[[:space:]=]+(\"([^\"]*)\"|'([^']*)'|([^[:space:]]+))"
if [[ "$cmd" =~ $body_pat ]]; then
  body="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
  # --body "$(cat <<EOF ...)": the regex stops at the first inner quote; read the heredoc.
  case "$body" in '$('*) body=$(heredoc_body "$cmd") || body="" ;; esac
  found_source=1
elif [[ "$cmd" =~ $short_pat ]]; then
  body="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
  found_source=1
else
  file_pat="(--body-file|-F)[[:space:]=]+(\"([^\"]*)\"|'([^']*)'|([^[:space:]]+))"
  if [[ "$cmd" =~ $file_pat ]]; then
    bf="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
    if [ "$bf" = "-" ]; then
      if body=$(heredoc_body "$cmd") && [ -n "$body" ]; then
        found_source=1
      fi
    else
      resolved=$(resolve_path "$bf")
      if [ -f "$resolved" ] && [ -r "$resolved" ]; then
        body=$(cat "$resolved" 2>/dev/null)
        found_source=1
      fi
    fi
  fi
fi

# No --body/-b and no --body-file/-F: an --editor session or the web flow. Cannot see
# the text, so let it through rather than block blind.
[ "$found_source" = "1" ] || exit 0

[ "${#body}" -ge 40 ] || exit 0

first=$(sed -E 's/^[[:space:]]+//' <<<"$body" | head -c1)
[ "$first" = "@" ] && exit 0

grep -qF "$marker" <<<"$body" && exit 0
footer_ok && grep -qF "$footer" <<<"$body" && exit 0

cat >&2 <<'MSG'
Blocked by rig/guard/gh-body-stamp: agent-posted text carries no marker. Append this line to the body: Posted by an agent under the operator's account. Bypass with STAMP_GATE=skip.
MSG
exit 2
