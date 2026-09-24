#!/bin/bash
# mage:rig/guard/no-haiku
# PreToolUse(Agent) hook: never Haiku for real work.
# Absence of model is out of jurisdiction; runtime defaults are unblocked.
# See issue #77.
# Rung: hook. Skipped: impossible (no deny rule restricts subagent model selection), check (the model exists only at spawn time).
set -u
in=$(cat)

_jlib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/json.sh"
[ -f "$_jlib" ] || _jlib="$(cd "$(dirname "$0")" && pwd)/lib/json.sh"
[ -f "$_jlib" ] && . "$_jlib"
type json_get >/dev/null 2>&1 || json_get() { return 1; }

_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

if [ -z "${in//[[:space:]]/}" ] || ! model=$(json_get "$in" "" .tool_input.model); then
  echo "no-haiku: could not read input." >&2
  exit 0
fi

[ -z "$model" ] && exit 0

case "${model,,}" in
  *haiku*)
    echo "Blocked by routing doctrine (dotfiles/AGENTS.md): never use Haiku. Pick sonnet or above." >&2
    echo "mage:rig/guard/no-haiku" >&2
    tool=$(json_get "$in" "Agent" .tool_name)
    report_guard "rig/guard/no-haiku" "$tool" "$model"
    exit 2
    ;;
esac

exit 0
