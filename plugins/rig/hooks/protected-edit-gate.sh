#!/bin/bash
# mage:rig/guard/protected-edit-gate
# PreToolUse(Edit|Write|NotebookEdit) hook: block edits to the loose skill copies under
# ~/.claude/skills and ~/.agents/skills (dedupe.sh overwrites them; the source is plugins/rig),
# and to the import line of ~/.claude/CLAUDE.md (machine-local rules go below it).
# Refs #123. Rung: hook. Skipped: impossible (no deny rule can see a path prefix), check (the damage is done by then).
set -u
in=$(cat)
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0
tool=$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null) || tool=""
home="${PROTECTED_EDIT_HOME:-$HOME}"

_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

case "$path" in
  "$home"/.claude/skills/*|"$home"/.agents/skills/*)
    cat >&2 <<MSG
Blocked by rig/guard/protected-edit-gate: $path is a loose copy that dedupe.sh removes after the
next plugin load. Edit plugins/rig/skills in the agent-rig checkout, commit, push (README §Editing).
MSG
    report_guard "rig/guard/protected-edit-gate" "$tool" "$path"
    exit 2 ;;
  "$home"/.claude/CLAUDE.md) ;;
  *) exit 0 ;;
esac

# ~/.claude/CLAUDE.md: the first @ line is the import. Rebuild the file the call would leave and
# require that line to survive as an exact line; a substring or a partial edit does not count.
import=$(grep -m1 '^@' "$path" 2>/dev/null || true)
[ -n "$import" ] || exit 0
if [ "$tool" = "Write" ]; then
  proposed=$(jq -r '.tool_input.content // ""' <<<"$in" 2>/dev/null) || proposed=""
else
  old=$(jq -r '.tool_input.old_string // ""' <<<"$in" 2>/dev/null) || old=""
  new=$(jq -r '.tool_input.new_string // ""' <<<"$in" 2>/dev/null) || new=""
  all=$(jq -r '.tool_input.replace_all // false' <<<"$in" 2>/dev/null) || all=false
  proposed=$(cat "$path" 2>/dev/null) || proposed=""
  if [ -n "$old" ]; then
    if [ "$all" = "true" ]; then proposed=${proposed//"$old"/"$new"}; else proposed=${proposed/"$old"/"$new"}; fi
  fi
fi
grep -qxF -- "$import" <<<"$proposed" && exit 0
cat >&2 <<MSG
Blocked by rig/guard/protected-edit-gate: ~/.claude/CLAUDE.md is a one-line import ($import) plus
machine-local rules below it. Everything above that line is edited in dotfiles/AGENTS.md in the
agent-rig checkout. Add machine-local rules below the import instead.
MSG
report_guard "rig/guard/protected-edit-gate" "$tool" "$path"
exit 2
