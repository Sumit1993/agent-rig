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

cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null) || cwd=""

resolve_path() {
  local f="$1"
  case "$f" in
    \~/*|\~) f="$HOME${f#\~}" ;;
  esac
  case "$f" in
    /*) ;;
    *) [ -n "$cwd" ] && f="$cwd/$f" ;;
  esac
  printf '%s' "$f"
}

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

grep -qF "Posted by an agent under the operator's account." <<<"$body" && exit 0
if [ "$sub" = "pr" ] && { [ "$verb" = "create" ] || [ "$verb" = "edit" ]; }; then
  grep -qF 'Generated with [Claude Code]' <<<"$body" && exit 0
fi

cat >&2 <<'MSG'
Blocked by rig/guard/gh-body-stamp: agent-posted text carries no marker. Append this line to the body: Posted by an agent under the operator's account. Bypass with STAMP_GATE=skip.
MSG
exit 2
