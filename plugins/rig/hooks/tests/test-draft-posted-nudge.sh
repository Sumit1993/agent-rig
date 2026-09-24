#!/bin/bash
# Regression suite for draft-posted-nudge.sh (PostToolUse Bash). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/draft-posted-nudge.sh"
fails=0
export AI_CONTEXT_ROOT=$(mktemp -d)
export DRAFT_POSTED_STATE_DIR=$(mktemp -d)
TMPDIR_CWD=$(mktemp -d)
cleanup() { rm -rf "$AI_CONTEXT_ROOT" "$DRAFT_POSTED_STATE_DIR" "$TMPDIR_CWD"; }
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
  local session=$1 cmd=$2 stderr=${3:-} cwd=${4:-} stdout=${5-https://github.com/o/r/issues/5#issuecomment-1}
  jq -n --arg s "$session" --arg c "$cmd" --arg err "$stderr" --arg cwd "$cwd" --arg out "$stdout" \
    '{"session_id": $s, "tool_input": {"command": $c}, "tool_response": {"stdout": $out, "stderr": $err}, "cwd": $cwd}' | "$HOOK"
}

# 2. gh issue comment 5 --body-file $ROOT/kit/1-x/drafts/c.md with empty stderr prints nudge naming that path and rm.
mkdir -p "$AI_CONTEXT_ROOT/kit/1-x/drafts"
echo "draft content" > "$AI_CONTEXT_ROOT/kit/1-x/drafts/c.md"
out=$(run_hook "sess1" "gh issue comment 5 --body-file $AI_CONTEXT_ROOT/kit/1-x/drafts/c.md" "")
rc=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if [ "$rc" -eq 0 ] && grep -qF "$AI_CONTEXT_ROOT/kit/1-x/drafts/c.md" <<<"$ctx" && grep -q 'rm' <<<"$ctx"; then
  echo "PASS: posted draft prints nudge naming path and rm"
else
  echo "FAIL: posted draft (rc=$rc, ctx=$ctx)"; fails=$((fails + 1))
fi

# 3. Same file a second time prints nothing (dedupe is per file, not per session).
out=$(run_hook "sess_new" "gh issue comment 5 --body-file $AI_CONTEXT_ROOT/kit/1-x/drafts/c.md" "")
if [ -z "$out" ]; then
  echo "PASS: same draft file deduped per file"
else
  echo "FAIL: draft not deduped: $out"; fails=$((fails + 1))
fi

# 4. stderr HTTP 422 prints nothing; stderr containing GraphQL prints nothing.
echo "draft 2" > "$AI_CONTEXT_ROOT/kit/1-x/drafts/c2.md"
out=$(run_hook "sess2" "gh issue comment 5 --body-file $AI_CONTEXT_ROOT/kit/1-x/drafts/c2.md" "HTTP 422 Unprocessable")
if [ -z "$out" ]; then
  echo "PASS: HTTP 422 stderr prints nothing"
else
  echo "FAIL: HTTP 422 printed: $out"; fails=$((fails + 1))
fi

out=$(run_hook "sess3" "gh issue comment 5 --body-file $AI_CONTEXT_ROOT/kit/1-x/drafts/c2.md" "GraphQL error: rate limit")
if [ -z "$out" ]; then
  echo "PASS: GraphQL stderr prints nothing"
else
  echo "FAIL: GraphQL stderr printed: $out"; fails=$((fails + 1))
fi

# A failed post whose stderr matches nothing still keeps its draft: no URL on stdout, no nudge.
echo "draft 3" > "$AI_CONTEXT_ROOT/kit/1-x/drafts/c3.md"
out=$(run_hook "sess_nourl" "gh issue comment 5 --body-file $AI_CONTEXT_ROOT/kit/1-x/drafts/c3.md" "something went sideways" "" "")
if [ -z "$out" ]; then
  echo "PASS: no URL on stdout prints nothing"
else
  echo "FAIL: no URL on stdout printed: $out"; fails=$((fails + 1))
fi

# 5. --body-file - prints nothing; a body file outside root prints nothing;
out=$(run_hook "sess4" "gh issue comment 5 --body-file -" "")
if [ -z "$out" ]; then
  echo "PASS: --body-file - prints nothing"
else
  echo "FAIL: --body-file - printed: $out"; fails=$((fails + 1))
fi

tmp_file=$(mktemp)
echo "outside" > "$tmp_file"
out=$(run_hook "sess5" "gh issue comment 5 --body-file $tmp_file" "")
rm -f "$tmp_file"
if [ -z "$out" ]; then
  echo "PASS: file outside root prints nothing"
else
  echo "FAIL: file outside root printed: $out"; fails=$((fails + 1))
fi

# $ROOT/kit/1-x/handoff.md, spec.md, plan.md print nothing.
for reserved in handoff.md spec.md spec-lane1.md plan.md; do
  touch "$AI_CONTEXT_ROOT/kit/1-x/$reserved"
  out=$(run_hook "sess_res" "gh issue comment 5 --body-file $AI_CONTEXT_ROOT/kit/1-x/$reserved" "")
  if [ -z "$out" ]; then
    echo "PASS: $reserved prints nothing"
  else
    echo "FAIL: $reserved printed: $out"; fails=$((fails + 1))
  fi
done

# 6. -F path and --body-file=path both count; a cwd-relative path resolves.
echo "draft f" > "$AI_CONTEXT_ROOT/kit/1-x/drafts/f.md"
out=$(run_hook "sess_f" "gh issue comment 5 -F $AI_CONTEXT_ROOT/kit/1-x/drafts/f.md" "")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -qF "$AI_CONTEXT_ROOT/kit/1-x/drafts/f.md" <<<"$ctx"; then
  echo "PASS: -F path counts"
else
  echo "FAIL: -F path (ctx=$ctx)"; fails=$((fails + 1))
fi

echo "draft eq" > "$AI_CONTEXT_ROOT/kit/1-x/drafts/eq.md"
out=$(run_hook "sess_eq" "gh issue comment 5 --body-file=$AI_CONTEXT_ROOT/kit/1-x/drafts/eq.md" "")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -qF "$AI_CONTEXT_ROOT/kit/1-x/drafts/eq.md" <<<"$ctx"; then
  echo "PASS: --body-file=path counts"
else
  echo "FAIL: --body-file=path (ctx=$ctx)"; fails=$((fails + 1))
fi

# Cwd-relative path resolves
mkdir -p "$TMPDIR_CWD/drafts"
echo "draft rel" > "$TMPDIR_CWD/drafts/rel.md"
# Move/symlink or point AI_CONTEXT_ROOT so TMPDIR_CWD/drafts/rel.md is under AI_CONTEXT_ROOT
mkdir -p "$AI_CONTEXT_ROOT/sub/drafts"
echo "draft under root" > "$AI_CONTEXT_ROOT/sub/drafts/rel.md"
out=$(run_hook "sess_cwd" "gh issue comment 5 --body-file drafts/rel.md" "" "$AI_CONTEXT_ROOT/sub")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -qF "$AI_CONTEXT_ROOT/sub/drafts/rel.md" <<<"$ctx"; then
  echo "PASS: cwd-relative path resolves"
else
  echo "FAIL: cwd-relative path (ctx=$ctx)"; fails=$((fails + 1))
fi

# 7. gh pr review 5 --body-file $ROOT/... counts.
echo "review draft" > "$AI_CONTEXT_ROOT/kit/1-x/drafts/rev.md"
out=$(run_hook "sess_rev" "gh pr review 5 --body-file $AI_CONTEXT_ROOT/kit/1-x/drafts/rev.md" "")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -qF "$AI_CONTEXT_ROOT/kit/1-x/drafts/rev.md" <<<"$ctx"; then
  echo "PASS: gh pr review counts"
else
  echo "FAIL: gh pr review (ctx=$ctx)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all draft-posted-nudge hook tests passed"
exit "$fails"
