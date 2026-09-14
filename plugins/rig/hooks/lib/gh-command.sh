#!/bin/bash
# Helpers for hooks that judge a gh command's body. They read what the command posts,
# not the rest of the Bash call around it. Refs #136, #123.

# Text from the first match of an extended regex to the end, so commands before it are ignored.
gh_from_invocation() { # <cmd> <ere>
  local cmd=$1 ere=$2
  [[ "$cmd" =~ $ere ]] || return 1
  printf '%s%s' "${BASH_REMATCH[0]}" "${cmd#*"${BASH_REMATCH[0]}"}"
}

# The shell spellings of an apostrophe inside single quotes, folded back to one character.
gh_normalize_quotes() {
  sed -e "s/'\\\\''/'/g" -e "s/'\"'\"'/'/g" -e "s/\\\\'/'/g" <<<"$1"
}

# Drop every heredoc body, keeping the line that opens it.
gh_strip_heredocs() {
  awk '
    tag != "" { t = $0; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t); if (t == tag) tag = ""; next }
    { print }
    match($0, /<<-?[[:space:]]*["\x27]?[A-Za-z_][A-Za-z0-9_]*/) {
      tag = substr($0, RSTART, RLENGTH); sub(/^<<-?[[:space:]]*["\x27]?/, "", tag)
    }
  ' <<<"$1"
}

# Expand a bare $NAME or ${NAME} to the value of the last NAME=value assignment in cmd.
gh_expand_var() { # <cmd> <word>
  local cmd=$1 word=$2 name val pat
  [[ "$word" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]] || { printf '%s' "$word"; return; }
  name=${BASH_REMATCH[1]}
  pat="(^|[;&|[:space:]])${name}=(\"([^\"]*)\"|'([^']*)'|([^[:space:];&|]+))"
  val=""
  while [[ "$cmd" =~ $pat ]]; do
    val="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
    cmd=${cmd#*"${BASH_REMATCH[0]}"}
  done
  if [ -n "$val" ]; then printf '%s' "$val"; else printf '%s' "$word"; fi
}

gh_resolve_path() { # <cwd> <path>
  local cwd=$1 f=$2
  case "$f" in \~/*|\~) f="$HOME${f#\~}" ;; esac
  case "$f" in /*) ;; *) [ -n "$cwd" ] && f="$cwd/$f" ;; esac
  printf '%s' "$f"
}
