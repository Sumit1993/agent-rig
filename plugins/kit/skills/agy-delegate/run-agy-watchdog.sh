#!/bin/bash
# Usage: run-agy-watchdog.sh <worktree> <promptfile> <outfile> <expected_commits> <timeout> [model]
# Runs agy headless; kills it if it hangs after completing its work
# (activity log stale >3min AND >=expected commits ahead of origin/main AND clean tree).
# Always appends the AGY_EXITED sentinel to <outfile> — wait on that, per the anti-stall skill.
set -u
WT="$1"; PROMPT="$2"; OUT="$3"; EXPECT="$4"; TMOUT="$5"
MODEL="${6:-gemini-3.8-flash-high}"

# agy's own --log-file streams; stdout holds one JSON envelope written only at the end.
# Staleness must key on the streaming log, or every run looks hung until it finishes.
SLUG="agy-$(basename "$PROMPT" .md)-$$-$(date +%s)"
ACTIVITY="${OUT%.*}.activity.log"

: > "$ACTIVITY"
cd "$WT" || { echo "WATCHDOG: worktree missing" >&2; echo "AGY_EXITED rc=1 status=NO_WORKTREE" >> "$ACTIVITY"; exit 1; }
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AGY_VERSION=$(agy --version 2>/dev/null | head -1 || true)
# Sidecar metadata written before launch so early deaths are attributable. Issue #62.
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg slug "$SLUG" \
    --arg model "$MODEL" \
    --arg prompt_file "$PROMPT" \
    --arg worktree "$WT" \
    --arg activity_log "$ACTIVITY" \
    --arg envelope "$OUT" \
    --arg started_at "$STARTED_AT" \
    --arg agy_version "$AGY_VERSION" \
    --arg expected_commits "$EXPECT" \
    --arg print_timeout "$TMOUT" \
    '{
      slug: $slug,
      model: $model,
      prompt_file: $prompt_file,
      worktree: $worktree,
      activity_log: $activity_log,
      envelope: $envelope,
      started_at: $started_at,
      agy_version: $agy_version,
      expected_commits: ($expected_commits | tonumber? // $expected_commits),
      print_timeout: $print_timeout
    }' > "$OUT.meta.json" 2>/dev/null || true
fi

agy --model "$MODEL" --log-file "$ACTIVITY" --output-format json \
  -p "$(cat "$PROMPT")" \
  --dangerously-skip-permissions --print-timeout "$TMOUT" > "$OUT" 2> "$OUT.err" &
PID=$!
echo "WATCHDOG: agy pid $PID slug $SLUG activity $ACTIVITY" >&2

while kill -0 "$PID" 2>/dev/null; do
  sleep 60
  now=$(date +%s); mt=$(stat -c %Y "$ACTIVITY" 2>/dev/null || echo "$now")
  if [ $((now - mt)) -gt 180 ]; then
    ahead=$(git -C "$WT" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
    dirty=$(git -C "$WT" status --porcelain 2>/dev/null | head -1)
    if [ "$ahead" -ge "$EXPECT" ] && [ -z "$dirty" ]; then
      kill -9 "$PID" 2>/dev/null
      echo "WATCHDOG: killed hung agy (work complete: $ahead commits, clean tree, log stale)" >> "$ACTIVITY"
      break
    fi
  fi
done
wait "$PID" 2>/dev/null
RC=$?

# The sentinel goes to the activity log, never to $OUT: appending to $OUT would make the
# JSON envelope unparseable, and an unparseable envelope is how truncation is detected.
# conversation_id is the resume handle; surface it so a salvage does not have to re-prompt.
CID=$(jq -r '.conversation_id // empty' "$OUT" 2>/dev/null)
STATUS=$(jq -r '.status // empty' "$OUT" 2>/dev/null)
ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BYTES=$(stat -c %s "$OUT" 2>/dev/null || echo 0)

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg slug "$SLUG" \
    --arg model "$MODEL" \
    --arg prompt_file "$PROMPT" \
    --arg worktree "$WT" \
    --arg activity_log "$ACTIVITY" \
    --arg envelope "$OUT" \
    --arg started_at "$STARTED_AT" \
    --arg agy_version "$AGY_VERSION" \
    --arg expected_commits "$EXPECT" \
    --arg print_timeout "$TMOUT" \
    --arg rc "$RC" \
    --arg status "${STATUS:-UNPARSEABLE}" \
    --arg conversation_id "${CID:-}" \
    --arg ended_at "$ENDED_AT" \
    --arg envelope_bytes "$BYTES" \
    '{
      slug: $slug,
      model: $model,
      prompt_file: $prompt_file,
      worktree: $worktree,
      activity_log: $activity_log,
      envelope: $envelope,
      started_at: $started_at,
      agy_version: $agy_version,
      expected_commits: ($expected_commits | tonumber? // $expected_commits),
      print_timeout: $print_timeout,
      rc: ($rc | tonumber? // $rc),
      status: $status,
      conversation_id: $conversation_id,
      ended_at: $ended_at,
      envelope_bytes: ($envelope_bytes | tonumber? // $envelope_bytes)
    }' > "$OUT.meta.json" 2>/dev/null || true
fi

echo "AGY_EXITED rc=$RC model=$MODEL status=${STATUS:-UNPARSEABLE} cid=${CID:-none} out=$OUT bytes=$(stat -c %s "$OUT" 2>/dev/null || echo 0)" >> "$ACTIVITY"
