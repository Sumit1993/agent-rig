#!/bin/bash
# Regression suite for ai-context-write-nudge.sh (PreToolUse Write|Edit|NotebookEdit). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/ai-context-write-nudge.sh"
fails=0
export AI_CONTEXT_ROOT=$(mktemp -d)
export AI_CONTEXT_NUDGE_STATE_DIR=$(mktemp -d)
cleanup() { rm -rf "$AI_CONTEXT_ROOT" "$AI_CONTEXT_NUDGE_STATE_DIR"; }
trap cleanup EXIT

# 1. Proves printf 'x' and printf '{}' exit 0 with no output.
out=$(printf 'x' | "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: malformed stdin exits 0 with no output"
else
  echo "FAIL: malformed stdin (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

out=$(printf '{}' | "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: empty payload exits 0 with no output"
else
  echo "FAIL: empty payload (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

run_hook() {
  local session=$1 tool=$2 field=$3 path=$4
  jq -n --arg s "$session" --arg t "$tool" --arg f "$field" --arg p "$path" \
    '{"session_id": $s, "tool_name": $t, "tool_input": {($f): $p}}' | "$HOOK"
}

# 2. $ROOT/foo-ruling.md prints both layout nudge and ruling nudge.
out=$(run_hook "sess_ruling" "Write" "file_path" "$AI_CONTEXT_ROOT/foo-ruling.md")
rc=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if [ "$rc" -eq 0 ] && grep -q '<repo>/<issue-or-pr>-<slug>/' <<<"$ctx" && grep -q 'did not happen' <<<"$ctx"; then
  echo "PASS: foo-ruling.md prints both layout and ruling nudges"
else
  echo "FAIL: foo-ruling.md (rc=$rc, ctx=$ctx)"; fails=$((fails + 1))
fi

# 3. $ROOT/kit/123-split/notes.md prints nothing.
out=$(run_hook "sess_notes" "Write" "file_path" "$AI_CONTEXT_ROOT/kit/123-split/notes.md")
if [ -z "$out" ]; then
  echo "PASS: kit/123-split/notes.md prints nothing"
else
  echo "FAIL: kit/123-split/notes.md printed: $out"; fails=$((fails + 1))
fi

# $ROOT/state/x, $ROOT/agy-logs/x, $ROOT/telemetry/x print nothing.
out=$(run_hook "sess_tool1" "Write" "file_path" "$AI_CONTEXT_ROOT/state/x")
if [ -z "$out" ]; then
  echo "PASS: state/x prints nothing"
else
  echo "FAIL: state/x printed: $out"; fails=$((fails + 1))
fi

out=$(run_hook "sess_tool2" "Write" "file_path" "$AI_CONTEXT_ROOT/agy-logs/x")
if [ -z "$out" ]; then
  echo "PASS: agy-logs/x prints nothing"
else
  echo "FAIL: agy-logs/x printed: $out"; fails=$((fails + 1))
fi

out=$(run_hook "sess_tool3" "Write" "file_path" "$AI_CONTEXT_ROOT/telemetry/x")
if [ -z "$out" ]; then
  echo "PASS: telemetry/x prints nothing"
else
  echo "FAIL: telemetry/x printed: $out"; fails=$((fails + 1))
fi

# 4. $ROOT/kit/123-split/spec.md prints only the ruling nudge.
out=$(run_hook "sess_spec" "Write" "file_path" "$AI_CONTEXT_ROOT/kit/123-split/spec.md")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -q 'did not happen' <<<"$ctx" && ! grep -q '<repo>/<issue-or-pr>-<slug>/' <<<"$ctx"; then
  echo "PASS: kit/123-split/spec.md prints only the ruling nudge"
else
  echo "FAIL: kit/123-split/spec.md (ctx=$ctx)"; fails=$((fails + 1))
fi

# 5. A path outside the root prints nothing.
out=$(run_hook "sess_outside" "Write" "file_path" "/tmp/outside-spec.md")
if [ -z "$out" ]; then
  echo "PASS: path outside root prints nothing"
else
  echo "FAIL: path outside root printed: $out"; fails=$((fails + 1))
fi

# notebook_path is honoured like file_path.
out=$(run_hook "sess_nb" "NotebookEdit" "notebook_path" "$AI_CONTEXT_ROOT/foo-ruling.md")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -q '<repo>/<issue-or-pr>-<slug>/' <<<"$ctx" && grep -q 'did not happen' <<<"$ctx"; then
  echo "PASS: notebook_path is honoured like file_path"
else
  echo "FAIL: notebook_path (ctx=$ctx)"; fails=$((fails + 1))
fi

# 6. Once per session per kind.
out1=$(run_hook "sess_once" "Write" "file_path" "$AI_CONTEXT_ROOT/kit/123-split/spec.md")
out2=$(run_hook "sess_once" "Write" "file_path" "$AI_CONTEXT_ROOT/kit/123-split/decision.md")
if [ -n "$out1" ] && [ -z "$out2" ]; then
  echo "PASS: ruling nudge fires once per session"
else
  echo "FAIL: ruling nudge repeated (out1=$out1, out2=$out2)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all ai-context-write-nudge hook tests passed"
exit "$fails"
