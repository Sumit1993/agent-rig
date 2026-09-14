#!/bin/bash
set -euo pipefail

command -v duckdb >/dev/null 2>&1 || { echo "Error: duckdb not found on PATH" >&2; exit 1; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="${PROJECTS:-$HOME/.claude/projects}"
L="${AGY_LOGS:-$HOME/ai-context/agy-logs}"
B="${AGY_BRAIN:-$HOME/.gemini/antigravity-cli/brain}"

run_query() {
  duckdb -dark-mode -box <<EOF
SET VARIABLE projects = '$P'; SET VARIABLE agy_logs = '$L'; SET VARIABLE agy_brain = '$B';
SET VARIABLE session_id = '${2:-}'; SET VARIABLE since = '${3:-}';
.read "$1"
EOF
}

if [ $# -gt 0 ]; then
  q="$DIR/$(basename "$1" .sql).sql"
  [ -f "$q" ] || { echo "Query not found: $q" >&2; exit 1; }
  sid="${2:-}"; since=""
  [ "${3:-}" = "--since" ] && since="${4:-}"
  run_query "$q" "$sid" "$since"
  if [ "$(basename "$q")" = "session-resume.sql" ] && [ -n "$sid" ]; then
    while IFS= read -r wt; do
      [ -n "$wt" ] && [ -d "$wt" ] && echo "--- $wt ---" && git -C "$wt" status --short || true
    done < <(duckdb -dark-mode -noheader -csv -c "SET VARIABLE projects = '$P'; SET VARIABLE session_id = '$sid';
      SELECT DISTINCT coalesce(
        regexp_extract(json::VARCHAR, '<worktreePath>([^<]+)</worktreePath>', 1),
        regexp_extract(json::VARCHAR, '\"path\"\\s*:\\s*\"([^\"\\n]+)\"', 1)
      )
      FROM read_ndjson_objects(getvariable('projects') || '/**/' || replace(getvariable('session_id'), '.jsonl', '') || '.jsonl')
      WHERE json::VARCHAR LIKE '%worktree%'" 2>/dev/null || true)
  fi
  exit 0
fi

t0=$(date +%s%N)
for sql in "$DIR"/*.sql; do
  [ -f "$sql" ] || continue
  [ "$(basename "$sql")" = "session-resume.sql" ] && continue
  q0=$(date +%s%N)
  out=$(run_query "$sql")
  q1=$(date +%s%N)
  dt=$(awk -v a="$q0" -v b="$q1" 'BEGIN { printf "%.2fs", (b-a)/1e9 }')
  echo "=== $(basename "$sql" .sql) ($dt) ==="
  printf '%s\n\n' "$out"
done
t1=$(date +%s%N)
echo "Total wall time: $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2fs", (b-a)/1e9 }')"
