#!/bin/bash
# Regression suite for issue-create-nudge.sh (PreToolUse Bash). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/issue-create-nudge.sh"
fails=0
export ISSUE_NUDGE_STATE_DIR=$(mktemp -d)
cleanup() { rm -rf "$ISSUE_NUDGE_STATE_DIR"; }
trap cleanup EXIT

got=$(printf 'not json' | "$HOOK" >/dev/null 2>&1; echo $?)
case "$got" in
  0|2) echo "PASS: junk stdin exits $got" ;;
  *) echo "FAIL: junk stdin rc=$got"; fails=$((fails + 1)) ;;
esac

run_hook() {
  local session=$1 cmd=$2
  jq -n --arg s "$session" --arg c "$cmd" '{"session_id": $s, "tool_input": {"command": $c}}' | "$HOOK"
}

# gh issue view never counts
out=$(run_hook "sess1" "gh issue view 123")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: gh issue view never counts"
else
  echo "FAIL: gh issue view (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# A search first keeps the counting cases below free of the search nudge
run_hook "sess1" 'gh search issues "quota lane" --owner Sumit1993' >/dev/null

# Call 1: prints nothing
out=$(run_hook "sess1" "gh issue create --title one")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: call 1 prints nothing"
else
  echo "FAIL: call 1 (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# Call 2: prints nothing
out=$(run_hook "sess1" "gh issue create --title two")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: call 2 prints nothing"
else
  echo "FAIL: call 2 (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# Call 3: prints JSON containing umbrella
out=$(run_hook "sess1" "gh issue create --title three")
rc=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if [ "$rc" -eq 0 ] && grep -q 'umbrella' <<<"$ctx"; then
  echo "PASS: call 3 prints JSON with umbrella"
else
  echo "FAIL: call 3 (rc=$rc, ctx=$ctx)"; fails=$((fails + 1))
fi

# Call 4: prints nothing
out=$(run_hook "sess1" "gh issue create --title four")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: call 4 prints nothing"
else
  echo "FAIL: call 4 (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# Different session starts at 1 (prints nothing on call 1)
run_hook "sess2" "gh issue list --state all --search quota" >/dev/null
out=$(run_hook "sess2" "gh issue create --title one")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: different session starts at 1"
else
  echo "FAIL: different session call 1 (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# A create with no search this session nudges toward triage, once
out=$(run_hook "sess3" "gh issue create --title unsearched")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
grep -q 'Load triage' <<<"$ctx" && echo "PASS: create without a search nudges toward triage" || { echo "FAIL: search nudge (out=$out)"; fails=$((fails + 1)); }
out=$(run_hook "sess3" "gh issue create --title again")
[ -z "$out" ] && echo "PASS: the search nudge fires once per session" || { echo "FAIL: search nudge repeated (out=$out)"; fails=$((fails + 1)); }

# Only a create in command position counts, not the words inside a body (#123).
run_hook "sess4" 'gh search issues "x" --owner Sumit1993' >/dev/null
mention=$(cat <<'CMDEOF'
gh issue comment 5 --body-file - <<'BODY'
gh issue create
gh issue create
BODY
CMDEOF
)
run_hook "sess4" "$mention" >/dev/null
run_hook "sess4" 'gh pr comment 5 --body "run gh issue create after the search"' >/dev/null
run_hook "sess4" "gh pr comment 5 --body 'planned steps; gh issue create'" >/dev/null
[ ! -f "$ISSUE_NUDGE_STATE_DIR/sess4" ] && echo "PASS: gh issue create inside a body is not counted" \
  || { echo "FAIL: body text counted as a create ($(cat "$ISSUE_NUDGE_STATE_DIR/sess4"))"; fails=$((fails + 1)); }
run_hook "sess4" 'cd repo && GH_REPO=a/b gh issue create --title real' >/dev/null
[ "$(cat "$ISSUE_NUDGE_STATE_DIR/sess4" 2>/dev/null)" = "1" ] && echo "PASS: a create after && with an env prefix counts" \
  || { echo "FAIL: chained create not counted"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo && echo "all issue-create-nudge hook tests passed"
exit "$fails"
