#!/bin/bash
# PreToolUse(Bash) hook: block gh issue/pr create/comment/edit/review citing scratch paths.
# Strips --body-file/-F token pairs so paths themselves never trigger false matches.
# Refs #123
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

grep -qE 'gh[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit|review)\b' <<<"$cmd" || exit 0
grep -q 'SCRATCH_GATE=skip' <<<"$cmd" && exit 0

cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null) || cwd=""

files=()
stripped="$cmd"
pat="(--body-file|-F)[[:space:]=]+(\"([^\"]*)\"|\x27([^\x27]*)\x27|([^[:space:]]+))"
while [[ "$stripped" =~ $pat ]]; do
  match="${BASH_REMATCH[0]}"
  arg="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
  files+=("$arg")
  stripped="${stripped/"$match"/}"
done

body_text="$stripped"
for f in "${files[@]}"; do
  [ "$f" = "-" ] && continue
  case "$f" in
    \~/*|\~) f="$HOME${f#\~}" ;;
  esac
  case "$f" in
    /*) ;;
    *) [ -n "$cwd" ] && f="$cwd/$f" ;;
  esac
  if [ -f "$f" ] && [ -r "$f" ]; then
    content=$(cat "$f" 2>/dev/null || true)
    body_text="$body_text"$'\n'"$content"
  fi
done

if grep -qE 'ai-context|/tmp/' <<<"$body_text"; then
  cat >&2 <<'MSG'
Blocked by kit/guard/gh-body-no-scratch: body text references scratch paths (ai-context or /tmp/).

A record copies its evidence in (AGENTS.md §Issues are the record). Scratch paths are wiped or live on another machine.

If this reference is intentional, bypass with SCRATCH_GATE=skip.
MSG
  exit 2
fi

exit 0
