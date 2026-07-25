#!/bin/bash
# Usage: run-agy-watchdog.sh <worktree> <promptfile> <logfile> <expected_commits> <timeout> [model]
# Runs agy headless; kills it if it hangs after completing its work
# (log stale >3min AND >=expected commits ahead of origin/main AND clean tree).
# Always appends the AGY_EXITED sentinel — wait on that, per the anti-stall skill.
set -u
WT="$1"; PROMPT="$2"; LOG="$3"; EXPECT="$4"; TMOUT="$5"
MODEL="${6:-Gemini 3.6 Flash (High)}"

cd "$WT" || { echo "WATCHDOG: worktree missing" > "$LOG"; echo "AGY_EXITED rc=1" >> "$LOG"; exit 1; }
agy --model "$MODEL" -p "$(cat "$PROMPT")" \
  --dangerously-skip-permissions --print-timeout "$TMOUT" > "$LOG" 2>&1 &
PID=$!
echo "WATCHDOG: agy pid $PID" >&2

while kill -0 "$PID" 2>/dev/null; do
  sleep 60
  now=$(date +%s); mt=$(stat -c %Y "$LOG" 2>/dev/null || echo "$now")
  if [ $((now - mt)) -gt 180 ]; then
    ahead=$(git -C "$WT" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
    dirty=$(git -C "$WT" status --porcelain 2>/dev/null | head -1)
    if [ "$ahead" -ge "$EXPECT" ] && [ -z "$dirty" ]; then
      kill -9 "$PID" 2>/dev/null
      echo "WATCHDOG: killed hung agy (work complete: $ahead commits, clean tree, log stale)" >> "$LOG"
      break
    fi
  fi
done
wait "$PID" 2>/dev/null
RC=$?
echo "AGY_EXITED rc=$RC log_bytes=$(stat -c %s "$LOG" 2>/dev/null || echo 0)" >> "$LOG"
