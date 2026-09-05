#!/bin/bash
# Regression suite for agy watchdog sidecar and model sentinel attribution.
set -u
SRC="$(cd "$(dirname "$0")/../../skills/agy-delegate" && pwd)/run-agy-watchdog.sh"
fails=0

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/wt"
echo "test prompt" > "$TMPDIR/prompt.md"

cat << 'STUB_AGY' > "$TMPDIR/bin/agy"
#!/bin/sh
if [ "$1" = "--version" ]; then echo "1.1.27"; exit 0; fi
if [ "${STUB_AGY_MODE:-}" = "ok" ]; then
  echo '{"status":"SUCCESS","conversation_id":"c123","num_turns":1,"response":"done"}'
  exit 0
fi
if [ "${STUB_AGY_MODE:-}" = "error0" ]; then
  echo '{"status":"ERROR","num_turns":0,"usage":{"input_tokens":0,"output_tokens":0}}'
  exit 1
fi
exit 1
STUB_AGY
cat << 'STUB_SLEEP' > "$TMPDIR/bin/sleep"
#!/bin/sh
exit 0
STUB_SLEEP
chmod +x "$TMPDIR/bin/agy" "$TMPDIR/bin/sleep"
PATH="$TMPDIR/bin:$PATH"

check() {
  local desc="$1" cond="$2"
  if eval "$cond"; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"; fails=$((fails + 1))
  fi
}

echo "-- missing worktree exit path"
bash "$SRC" "$TMPDIR/no-wt" "$TMPDIR/prompt.md" "$TMPDIR/out1.json" 0 10s model-wt >/dev/null 2>&1 || true
check "missing worktree sentinel carries model=" 'grep -q "model=model-wt" "$TMPDIR/out1.activity.log"'
check "missing worktree sidecar parses" 'jq -e . "$TMPDIR/out1.json.meta.json" >/dev/null 2>&1'
check "missing worktree status is NO_WORKTREE" '[ "$(jq -r .status "$TMPDIR/out1.json.meta.json")" = "NO_WORKTREE" ]'

echo "-- zero-byte envelope (agy exits without writing)"
STUB_AGY_MODE=fail bash "$SRC" "$TMPDIR/wt" "$TMPDIR/prompt.md" "$TMPDIR/out2.json" 0 10s model-fail >/dev/null 2>&1 || true
check "empty envelope sentinel carries model=" 'grep -q "model=model-fail" "$TMPDIR/out2.activity.log"'
check "empty envelope sidecar parses" 'jq -e . "$TMPDIR/out2.json.meta.json" >/dev/null 2>&1'
check "launched is false when envelope is empty" '[ "$(jq -r .launched "$TMPDIR/out2.json.meta.json")" = "false" ]'

echo "-- parseable ERROR with num_turns: 0 (rejected slug, quota death)"
STUB_AGY_MODE=error0 bash "$SRC" "$TMPDIR/wt" "$TMPDIR/prompt.md" "$TMPDIR/out4.json" 0 10s model-err >/dev/null 2>&1 || true
check "error0 sidecar parses" 'jq -e . "$TMPDIR/out4.json.meta.json" >/dev/null 2>&1'
check "launched is false for ERROR num_turns 0" '[ "$(jq -r .launched "$TMPDIR/out4.json.meta.json")" = "false" ]'

echo "-- successful run with num_turns: 1"
STUB_AGY_MODE=ok bash "$SRC" "$TMPDIR/wt" "$TMPDIR/prompt.md" "$TMPDIR/out3.json" 0 10s model-ok >/dev/null 2>&1 || true
check "launched sentinel carries model=" 'grep -q "model=model-ok" "$TMPDIR/out3.activity.log"'
check "launched sidecar parses" 'jq -e . "$TMPDIR/out3.json.meta.json" >/dev/null 2>&1'
check "launched is true when num_turns is 1" '[ "$(jq -r .launched "$TMPDIR/out3.json.meta.json")" = "true" ]'

[ "$fails" -eq 0 ] && echo && echo "all test-agy-sidecar tests passed"
exit "$fails"
