#!/bin/bash
# PreToolUse(Agent) hook: never Haiku for real work.
# Absence of model is out of jurisdiction; runtime defaults are unblocked.
# See issue #77.
set -u
in=$(cat)

if [ -z "${in//[[:space:]]/}" ] || ! model=$(jq -r '.tool_input.model // ""' <<<"$in" 2>/dev/null); then
  echo "no-haiku: could not read input." >&2
  exit 0
fi

[ -z "$model" ] && exit 0

case "${model,,}" in
  *haiku*)
    echo "Blocked by routing doctrine (dotfiles/AGENTS.md): never use Haiku. Pick sonnet or above." >&2
    exit 2
    ;;
esac

exit 0
