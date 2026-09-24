#!/bin/bash
# Regression suite for gh-write-nudge.sh (PreToolUse Bash). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/gh-write-nudge.sh"
fails=0
export GH_WRITE_NUDGE_STATE_DIR=$(mktemp -d)
TMPDIR_CWD=$(mktemp -d)
cleanup() { rm -rf "$GH_WRITE_NUDGE_STATE_DIR" "$TMPDIR_CWD"; }
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
  local session=$1 cmd=$2 cwd=${3:-}
  jq -n --arg s "$session" --arg c "$cmd" --arg cwd "$cwd" \
    '{"session_id": $s, "tool_input": {"command": $c}, "cwd": $cwd}' | "$HOOK"
}

# 2. gh issue comment 5 --body "## Handoff\nstate" prints additionalContext containing handoff.
cmd="gh issue comment 5 --body \"## Handoff
state\""
out=$(run_hook "sess_handoff" "$cmd")
rc=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if [ "$rc" -eq 0 ] && grep -qi 'handoff' <<<"$ctx"; then
  echo "PASS: body with ## Handoff prints handoff nudge"
else
  echo "FAIL: body with ## Handoff (rc=$rc, ctx=$ctx)"; fails=$((fails + 1))
fi

# 3. 41-line body via --body-file - heredoc prints handoff nudge; 10-line one does not (new session).
body41=$(seq 1 41)
cmd41=$(cat <<EOF
gh issue comment 5 --body-file - <<'BODY'
$body41
BODY
EOF
)
out=$(run_hook "sess_41" "$cmd41")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -qi 'handoff' <<<"$ctx"; then
  echo "PASS: 41-line heredoc prints handoff nudge"
else
  echo "FAIL: 41-line heredoc (ctx=$ctx)"; fails=$((fails + 1))
fi

body10=$(seq 1 10)
cmd10=$(cat <<EOF
gh issue comment 5 --body-file - <<'BODY'
$body10
BODY
EOF
)
out=$(run_hook "sess_10" "$cmd10")
if [ -z "$out" ]; then
  echo "PASS: 10-line heredoc prints nothing"
else
  echo "FAIL: 10-line heredoc printed: $out"; fails=$((fails + 1))
fi

# 4. Bare citation nudges:
# --body "see #12 now" prints nudge containing #N - title
out=$(run_hook "sess_cite1" 'gh issue comment 5 --body "see #12 now"')
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -q '#N - title' <<<"$ctx"; then
  echo "PASS: bare citation prints #N - title nudge"
else
  echo "FAIL: bare citation (ctx=$ctx)"; fails=$((fails + 1))
fi

# --body "see #12 - the fix" prints nothing (new session)
out=$(run_hook "sess_cite2" 'gh issue comment 5 --body "see #12 - the fix"')
if [ -z "$out" ]; then
  echo "PASS: cited with title prints nothing"
else
  echo "FAIL: cited with title printed: $out"; fails=$((fails + 1))
fi

# --body "&#123;" prints nothing
out=$(run_hook "sess_cite3" 'gh issue comment 5 --body "&#123;"')
if [ -z "$out" ]; then
  echo "PASS: html entity prints nothing"
else
  echo "FAIL: html entity printed: $out"; fails=$((fails + 1))
fi

# 5. gh pr create --title x --body y prints nudge containing --draft
out=$(run_hook "sess_pr1" 'gh pr create --title x --body y')
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -q -- '--draft' <<<"$ctx"; then
  echo "PASS: non-draft gh pr create prints draft nudge"
else
  echo "FAIL: non-draft gh pr create (ctx=$ctx)"; fails=$((fails + 1))
fi

# gh pr create --draft ... and gh pr create -d ... print nothing (new sessions)
out=$(run_hook "sess_pr2" 'gh pr create --draft --title x --body y')
if [ -z "$out" ]; then
  echo "PASS: gh pr create --draft prints nothing"
else
  echo "FAIL: gh pr create --draft printed: $out"; fails=$((fails + 1))
fi

out=$(run_hook "sess_pr3" 'gh pr create -d --title x --body y')
if [ -z "$out" ]; then
  echo "PASS: gh pr create -d prints nothing"
else
  echo "FAIL: gh pr create -d printed: $out"; fails=$((fails + 1))
fi

# 6. Each kind fires once per session: repeat same command in same session, expect no output.
out1=$(run_hook "sess_once" 'gh pr create --title x --body y')
out2=$(run_hook "sess_once" 'gh pr create --title x --body y')
if [ -n "$out1" ] && [ -z "$out2" ]; then
  echo "PASS: nondraft nudge fires once per session"
else
  echo "FAIL: nondraft once per session (out1=$out1, out2=$out2)"; fails=$((fails + 1))
fi

# 7. gh issue view 5 and gh pr list print nothing.
out=$(run_hook "sess_view" 'gh issue view 5')
if [ -z "$out" ]; then
  echo "PASS: gh issue view prints nothing"
else
  echo "FAIL: gh issue view printed: $out"; fails=$((fails + 1))
fi

out=$(run_hook "sess_list" 'gh pr list')
if [ -z "$out" ]; then
  echo "PASS: gh pr list prints nothing"
else
  echo "FAIL: gh pr list printed: $out"; fails=$((fails + 1))
fi

# 8. Body file under a cwd-relative path is read: 41-line file, --body-file rel.md with cwd set.
seq 1 41 > "$TMPDIR_CWD/rel.md"
out=$(run_hook "sess_rel" 'gh issue comment 5 --body-file rel.md' "$TMPDIR_CWD")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -qi 'handoff' <<<"$ctx"; then
  echo "PASS: cwd-relative 41-line body file triggers handoff nudge"
else
  echo "FAIL: cwd-relative body file (ctx=$ctx)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all gh-write-nudge hook tests passed"
exit "$fails"
