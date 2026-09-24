#!/bin/bash
# Regression suite for ai-context-sweep.sh. Refs #123.
set -u
SWEEP_SH="$(cd "$(dirname "$0")/.." && pwd)/ai-context-sweep.sh"
fails=0

TMP_DIR=$(mktemp -d)
BIN_DIR="$TMP_DIR/bin"
ROOT_DIR="$TMP_DIR/ai-context"
META_FILE="$TMP_DIR/repo-meta.json"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$ROOT_DIR"

# Fake registry pointing to myowner/myrepo
cat > "$META_FILE" <<'EOF'
{
  "myowner/myrepo": {
    "canon": null
  }
}
EOF

# Fake gh binary: answers CLOSED for issue 1, OPEN for 2, 404 for 3
cat > "$BIN_DIR/gh" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    1) echo '{"state":"CLOSED","closedAt":"2026-01-01T00:00:00Z"}'; exit 0 ;;
    2) echo '{"state":"OPEN","closedAt":null}'; exit 0 ;;
    3) echo '{"message":"Not Found"}' >&2; exit 1 ;;
  esac
done
exit 1
EOF
chmod +x "$BIN_DIR/gh"

export PATH="$BIN_DIR:$PATH"
export AI_CONTEXT_ROOT="$ROOT_DIR"
export RIG_REPO_META="$META_FILE"

# Build candidate and test directories:
# 1. Closed candidate under myrepo
mkdir -p "$ROOT_DIR/myrepo/1-closed"
echo "closed note" > "$ROOT_DIR/myrepo/1-closed/notes.md"

# 2. Open candidate under myrepo
mkdir -p "$ROOT_DIR/myrepo/2-open"
echo "open note" > "$ROOT_DIR/myrepo/2-open/notes.md"

# 3. 404 candidate under myrepo
mkdir -p "$ROOT_DIR/myrepo/3-missing"
echo "missing note" > "$ROOT_DIR/myrepo/3-missing/notes.md"

# 4. Tool directories to skip
mkdir -p "$ROOT_DIR/state" "$ROOT_DIR/telemetry" "$ROOT_DIR/backups" "$ROOT_DIR/vendor" "$ROOT_DIR/agy-logs"
echo "state" > "$ROOT_DIR/state/state.txt"
echo "telem" > "$ROOT_DIR/telemetry/telem.txt"
echo "backup" > "$ROOT_DIR/backups/backup.txt"
echo "vendor" > "$ROOT_DIR/vendor/vendor.txt"
echo "log" > "$ROOT_DIR/agy-logs/log.txt"

# 5. Empty directory
mkdir -p "$ROOT_DIR/empty-dir"

# 6. Loose file at top level
echo "loose" > "$ROOT_DIR/loose.txt"

# --- Dry-run tests ---
out=$(bash "$SWEEP_SH")

# Case 1: closed listed
if grep -qE "CLOSED 2026-01-01T00:00:00Z [^ ]+ $ROOT_DIR/myrepo/1-closed" <<<"$out"; then
  echo "PASS: closed candidate listed"
else
  echo "FAIL: closed candidate not listed in output: $out"; fails=$((fails + 1))
fi

# Case 2: open listed
if grep -q "OPEN $ROOT_DIR/myrepo/2-open" <<<"$out"; then
  echo "PASS: open candidate listed"
else
  echo "FAIL: open candidate not listed: $out"; fails=$((fails + 1))
fi

# Case 3: 404 skipped
if grep -q "SKIP 404 $ROOT_DIR/myrepo/3-missing" <<<"$out"; then
  echo "PASS: 404 candidate skipped"
else
  echo "FAIL: 404 candidate not skipped: $out"; fails=$((fails + 1))
fi

# Case 4: tool dirs skipped
if ! grep -qE 'state|telemetry|backups|vendor|agy-logs' <<<"$out"; then
  echo "PASS: tool dirs skipped"
else
  echo "FAIL: tool dirs appeared in output: $out"; fails=$((fails + 1))
fi

# Case 5: empty dir listed
if grep -q "EMPTY $ROOT_DIR/empty-dir" <<<"$out"; then
  echo "PASS: empty dir listed"
else
  echo "FAIL: empty dir not listed: $out"; fails=$((fails + 1))
fi

# Case 6: loose file counted
if grep -q "1 loose files at the top level" <<<"$out"; then
  echo "PASS: loose file counted"
else
  echo "FAIL: loose file count incorrect: $out"; fails=$((fails + 1))
fi

# Dry run must not remove anything
if [ -d "$ROOT_DIR/myrepo/1-closed" ] && [ -d "$ROOT_DIR/empty-dir" ]; then
  echo "PASS: dry run removed nothing"
else
  echo "FAIL: dry run removed files/dirs"; fails=$((fails + 1))
fi

# --- --delete tests ---
del_out=$(bash "$SWEEP_SH" --delete)

# Case 7: --delete removes exactly CLOSED and EMPTY entries
if [ ! -d "$ROOT_DIR/myrepo/1-closed" ] && [ ! -d "$ROOT_DIR/empty-dir" ]; then
  echo "PASS: --delete removed closed candidate and empty dir"
else
  echo "FAIL: --delete failed to remove closed/empty"; fails=$((fails + 1))
fi

if [ -d "$ROOT_DIR/myrepo/2-open" ] && [ -d "$ROOT_DIR/myrepo/3-missing" ] && \
   [ -d "$ROOT_DIR/state" ] && [ -d "$ROOT_DIR/agy-logs" ] && [ -f "$ROOT_DIR/loose.txt" ]; then
  echo "PASS: --delete preserved open, 404, tool dirs, and loose files"
else
  echo "FAIL: --delete removed preserved files/dirs"; fails=$((fails + 1))
fi

if grep -q "DELETED $ROOT_DIR/myrepo/1-closed" <<<"$del_out" && \
   grep -q "DELETED $ROOT_DIR/empty-dir" <<<"$del_out"; then
  echo "PASS: --delete printed DELETED for closed and empty entries"
else
  echo "FAIL: --delete output missing DELETED lines: $del_out"; fails=$((fails + 1))
fi

# An unreadable registry is an error, not an empty one.
echo "not json" > "$TMP_DIR/bad-meta.json"
RIG_REPO_META="$TMP_DIR/bad-meta.json" bash "$SWEEP_SH" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
  echo "PASS: invalid registry exits 1"
else
  echo "FAIL: invalid registry (rc=$rc)"; fails=$((fails + 1))
fi

# Two registry repos sharing a basename make their directory ambiguous; --delete leaves it.
cat > "$TMP_DIR/dup-meta.json" <<'JSON'
{ "owner-a/dup": {}, "owner-b/dup": {} }
JSON
mkdir -p "$ROOT_DIR/dup/1-closed"
echo "note" > "$ROOT_DIR/dup/1-closed/notes.md"
dup_out=$(RIG_REPO_META="$TMP_DIR/dup-meta.json" bash "$SWEEP_SH" --delete 2>&1)
if grep -q "SKIP AMBIGUOUS $ROOT_DIR/dup/1-closed" <<<"$dup_out" && [ -d "$ROOT_DIR/dup/1-closed" ]; then
  echo "PASS: ambiguous basename skipped and kept"
else
  echo "FAIL: ambiguous basename (out=$dup_out)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all ai-context-sweep tests passed"
exit "$fails"
