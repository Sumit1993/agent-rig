#!/bin/bash
# mage:rig/guard/organizer-seat
# PreToolUse(Edit|Write|NotebookEdit) hook: "the organizer does not type" (AGENTS.md
# §Orchestrator) only bites while delegates are working — editing when nothing is
# delegated is just doing the work. So this fires ONLY while an agy run is alive, and
# only once per session: a nudge at the moment the seat is being left, not a wall.
# Rung: hook. Skipped: impossible (editing is allowed when delegates are idle), check (delegate processes exist only at call time).
set -u
in=$(cat)

_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

pgrep -x agy >/dev/null 2>&1 || exit 0

session=$(jq -r '.session_id // "nosession"' <<<"$in" 2>/dev/null) || exit 0
state_dir=${ORGANIZER_SEAT_STATE_DIR:-$HOME/ai-context/state/organizer-seat}
mkdir -p "$state_dir" 2>/dev/null || exit 0
flag="$state_dir/$session"
[ -e "$flag" ] && exit 0
: > "$flag" 2>/dev/null || exit 0

live=$(pgrep -x agy | wc -l | tr -d ' ')
# Codex reports file edits as apply_patch; name whichever tool arrived (#141).
tool=$(jq -r '.tool_name // "Edit"' <<<"$in" 2>/dev/null)
cat >&2 <<MSG
Blocked once (AGENTS.md §Orchestrator/Organizer/Manager): $live agy run(s) are live and you
are editing files via $tool. The seat that keeps the whole goal in view decides what runs next
and checks delegated claims against evidence. It does not type.

If this edit belongs to a lane, send it there. If you are verifying a delegate's claim, or
this is small and yours, proceed — re-issue and it will pass. This fires once per session.
mage:rig/guard/organizer-seat
MSG
report_guard "rig/guard/organizer-seat" "$tool" "$live live runs"
exit 2
