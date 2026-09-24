#!/usr/bin/env bash
# Append-only sync of agent run records to R2. Layout is raw/<source>/<date>/<file>,
# so DuckDB httpfs can read a prefix directly. Ruling: rig#89.
set -euo pipefail

BUCKET="${R2_BUCKET:-agent-raw}"
REMOTE="${RCLONE_REMOTE:-r2}"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY="--dry-run"

command -v rclone >/dev/null || { echo "rclone not found: see scripts/README-r2.md" >&2; exit 1; }

# Sources are named, never globbed from a parent: agy's conversations/*.db is 2.2 GB of
# protobuf superseded by the JSONL beside it, and must never be picked up by accident.
# A transcript still being appended to is skipped (--min-age) and a source whose rclone
# fails does not stop the next source. Story: rig#124.
sync_one() {
  local label="$1" src="$2" filter="$3"
  [ -d "$src" ] || { echo "skip $label: $src absent"; return 0; }
  echo "== $label"
  rclone copy $DRY "$src" "$REMOTE:$BUCKET/raw/$label/" \
    --include "$filter" \
    --immutable \
    --min-age "${MIN_AGE:-2h}" \
    --no-update-modtime \
    --transfers 16 \
    --stats-one-line --stats 10s || echo "warn: $label finished with errors (see above)" >&2
}

sync_one claude-code   "$HOME/.claude/projects"                  "**/*.jsonl"
sync_one agy-brain     "$HOME/.gemini/antigravity-cli/brain"     "**/transcript*.jsonl"
sync_one agy-envelopes "$HOME/ai-context/agy-logs"               "*.json"

echo
echo "bucket usage:"
rclone size "$REMOTE:$BUCKET" 2>/dev/null || true
