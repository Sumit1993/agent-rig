#!/bin/bash
# Usage: run-agy-watchdog.sh <worktree> <promptfile> <outfile> <expected_commits> <timeout> [model]
# Runs agy headless; kills it if it hangs after completing its work
# (activity log stale >3min AND >=expected commits ahead of origin/main AND clean tree).
# Always appends the AGY_EXITED sentinel to <outfile>, wait on that, per the anti-stall skill.
set -u
WT="$1"; PROMPT="$2"; OUT="$3"; EXPECT="$4"; TMOUT="$5"
MODEL="${6:-gemini-3.8-flash-high}"

WT=$(realpath -m "$WT")
PROMPT=$(realpath -m "$PROMPT")
OUT=$(realpath -m "$OUT")
ACTIVITY=$(realpath -m "${OUT%.*}.activity.log")
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# agy's own --log-file streams; stdout holds one JSON envelope written only at the end.
# Staleness must key on the streaming log, or every run looks hung until it finishes.
SLUG="agy-$(basename "$PROMPT" .md)-$$-$(date +%s)"

: > "$ACTIVITY"
cd "$WT" || {
  echo "WATCHDOG: worktree missing" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg slug "$SLUG" \
      --arg model "$MODEL" \
      --arg prompt_file "$PROMPT" \
      --arg worktree "$WT" \
      --arg started_at "$STARTED_AT" \
      '{
        slug: $slug,
        model: $model,
        prompt_file: $prompt_file,
        worktree: $worktree,
        started_at: $started_at,
        rc: 1,
        status: "NO_WORKTREE"
      }' > "$OUT.meta.json.tmp" 2>/dev/null && mv -f "$OUT.meta.json.tmp" "$OUT.meta.json" 2>/dev/null || rm -f "$OUT.meta.json.tmp" 2>/dev/null
  fi
  echo "AGY_EXITED rc=1 model=$MODEL status=NO_WORKTREE" >> "$ACTIVITY"
  exit 1
}
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
    --arg stderr_file "$OUT.err" \
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
      stderr_file: $stderr_file,
      started_at: $started_at,
      agy_version: $agy_version,
      expected_commits: ($expected_commits | tonumber? // $expected_commits),
      print_timeout: $print_timeout
    }' > "$OUT.meta.json.tmp" 2>/dev/null && mv -f "$OUT.meta.json.tmp" "$OUT.meta.json" 2>/dev/null || rm -f "$OUT.meta.json.tmp" 2>/dev/null
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
ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BYTES=$(stat -c %s "$OUT" 2>/dev/null || echo 0)

# Quota exhaustion records best-effort state and updates the sidecar. Issue #47.
QUOTA_EXHAUSTED=false
if command -v jq >/dev/null 2>&1; then
  ERR_MSG=$(jq -r 'if .error | type == "string" then .error elif .error != null then (.error | tostring) else "" end' "$OUT" 2>/dev/null || true)
  ERR_LOWER=$(printf '%s' "$ERR_MSG" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$ERR_LOWER" | grep -q 'quota' && printf '%s' "$ERR_LOWER" | grep -qE 'reached|resource[_ ]exhausted|429'; then
    QUOTA_EXHAUSTED=true
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    AGY_QUOTA="$SCRIPT_DIR/agy-quota.sh"
    if [ -f "$AGY_QUOTA" ]; then
      RESET_ARG=""
      if [[ "$ERR_MSG" =~ [Rr]esets?[[:space:]]+in[[:space:]]+([0-9]+[hms][0-9hms]*) ]]; then
        RESET_ARG="${BASH_REMATCH[1]}"
      elif [[ "$ERR_MSG" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:?[0-9]{2})?) ]]; then
        RESET_ARG="${BASH_REMATCH[1]}"
      fi
      if [ -n "$RESET_ARG" ]; then
        bash "$AGY_QUOTA" record "$MODEL" "$RESET_ARG" 2>/dev/null || true
      else
        bash "$AGY_QUOTA" record "$MODEL" 2>/dev/null || true
      fi
    fi
  fi
fi

if command -v jq >/dev/null 2>&1; then
  CID=$(jq -r '.conversation_id // empty' "$OUT" 2>/dev/null || true)
  STATUS=$(jq -r '.status // empty' "$OUT" 2>/dev/null || true)
  SENTINEL_STATUS="${STATUS:-UNPARSEABLE}"
  # launched is true only when at least one turn ran. num_turns: 0 means the
  # request was rejected before any work started (bad model, quota hit). Issue #50.
  TURNS=$(jq -r '(.num_turns // 0) | tonumber? // 0' "$OUT" 2>/dev/null || echo 0)
  LAUNCHED=false
  if [ "${TURNS:-0}" -gt 0 ] 2>/dev/null; then
    LAUNCHED=true
  fi
  jq -n \
    --arg slug "$SLUG" \
    --arg model "$MODEL" \
    --arg prompt_file "$PROMPT" \
    --arg worktree "$WT" \
    --arg activity_log "$ACTIVITY" \
    --arg envelope "$OUT" \
    --arg stderr_file "$OUT.err" \
    --arg started_at "$STARTED_AT" \
    --arg agy_version "$AGY_VERSION" \
    --arg expected_commits "$EXPECT" \
    --arg print_timeout "$TMOUT" \
    --arg rc "$RC" \
    --arg status "${STATUS:-UNPARSEABLE}" \
    --arg conversation_id "${CID:-}" \
    --arg ended_at "$ENDED_AT" \
    --arg envelope_bytes "$BYTES" \
    --argjson launched "$LAUNCHED" \
    --argjson quota_exhausted "$QUOTA_EXHAUSTED" \
    '{
      slug: $slug,
      model: $model,
      prompt_file: $prompt_file,
      worktree: $worktree,
      activity_log: $activity_log,
      envelope: $envelope,
      stderr_file: $stderr_file,
      started_at: $started_at,
      agy_version: $agy_version,
      expected_commits: ($expected_commits | tonumber? // $expected_commits),
      print_timeout: $print_timeout,
      rc: ($rc | tonumber? // $rc),
      status: $status,
      conversation_id: $conversation_id,
      ended_at: $ended_at,
      envelope_bytes: ($envelope_bytes | tonumber? // $envelope_bytes),
      launched: $launched,
      quota_exhausted: $quota_exhausted
    }' > "$OUT.meta.json.tmp" 2>/dev/null && mv -f "$OUT.meta.json.tmp" "$OUT.meta.json" 2>/dev/null || rm -f "$OUT.meta.json.tmp" 2>/dev/null
else
  CID=""
  STATUS=""
  SENTINEL_STATUS="NO_JQ"
fi

echo "AGY_EXITED rc=$RC model=$MODEL status=$SENTINEL_STATUS cid=${CID:-none} out=$OUT bytes=$(stat -c %s "$OUT" 2>/dev/null || echo 0)" >> "$ACTIVITY"
