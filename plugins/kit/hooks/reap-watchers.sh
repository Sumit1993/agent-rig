#!/bin/bash
# reap-watchers.sh [end|start] — keep watch processes from outliving their session.
# A monitor that survives a closed session injects its buffered event on resume,
# and that turn pays for the whole context window. Killing watchers is free:
# their seen-state is durable (~/ai-context/state/cr-watch), so re-arming never
# replays old events.
#   end   (SessionEnd)   kill all watcher processes
#   start (SessionStart) reap only orphans (PPID 1) left by sessions that died
#                        without the SessionEnd hook (crash, killed terminal)
# Caveat: `end` matches watchers from ALL live sessions; with concurrent
# sessions, re-arm in the surviving one.
set -u
mode="${1:-end}"
pattern='watch-coderabbit\.sh|merge-cascade\.sh'
if [ "$mode" = "start" ]; then
  for pid in $(pgrep -f "$pattern" 2>/dev/null); do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ "$ppid" = "1" ] && kill "$pid" 2>/dev/null
  done
else
  pkill -f "$pattern" 2>/dev/null
fi
exit 0
