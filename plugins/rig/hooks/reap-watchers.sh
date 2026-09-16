#!/bin/bash
# reap-watchers.sh [end|start] [--dry] — keep watch processes from outliving
# their session. A monitor that survives a closed session injects its buffered
# event on resume, and that turn pays for the whole context window. Killing
# watchers is free: their seen-state is durable (~/ai-context/state/cr-watch),
# so re-arming never replays old events.
# Rung: hook. Skipped: impossible (background processes survive session exit), check (orphans must be cleaned at lifecycle boundaries).
#
#   end   (SessionEnd)   kill only THIS session's watchers — those descending
#                        from this hook's own claude ancestor process. Watchers
#                        of concurrent sessions are untouched. If the session
#                        process cannot be identified, kill nothing (fail-safe;
#                        start-mode is the safety net).
#   start (SessionStart) reap orphans (PPID 1) left by sessions that died
#                        without the SessionEnd hook (crash, killed terminal).
#   --dry                print would-kill PIDs instead of killing.
set -u
mode="${1:-end}"
dry="${2:-}"
pattern='watch-coderabbit\.sh'

reap() {
  if [ "$dry" = "--dry" ]; then echo "would kill $1"; else kill "$1" 2>/dev/null; fi
}

ancestors() {  # print the PID ancestry of $1 (excluding 0/1), up to 15 levels
  local p="$1" i=0
  while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ] && [ "$i" -lt 15 ]; do
    echo "$p"
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
}

if [ "$mode" = "start" ]; then
  for pid in $(pgrep -f "$pattern" 2>/dev/null); do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ "$ppid" = "1" ] && reap "$pid"
  done
  exit 0
fi

# end: locate this session's claude process among the hook's ancestors. Match
# the CLI process itself (comm=claude, or node running the claude entrypoint) —
# never bash wrappers, whose cmdlines also mention ~/.claude paths.
sess=""
for p in $(ancestors "$$"); do
  comm=$(ps -o comm= -p "$p" 2>/dev/null | tr -d ' ')
  case "$comm" in
    claude*) sess="$p"; break;;
    node|node.exe)
      case "$(ps -o args= -p "$p" 2>/dev/null)" in
        *claude*) sess="$p"; break;;
      esac;;
  esac
done
[ -n "$sess" ] || exit 0

for pid in $(pgrep -f "$pattern" 2>/dev/null); do
  if ancestors "$pid" | grep -qx "$sess"; then
    reap "$pid"
  fi
done
exit 0
