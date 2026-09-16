#!/bin/bash
# Regression suite for merge-gate.sh (PreToolUse Bash). Refs #123, #20.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/merge-gate.sh"
fails=0

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
  local cmd=$1
  jq -n --arg c "$cmd" '{"tool_input": {"command": $c}}' | "$HOOK"
}

# 2. gh pr merge 139 --squash exits 2, stderr contains MERGE_OK=139
err=$(run_hook "gh pr merge 139 --squash" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'MERGE_OK=139' <<<"$err"; then
  echo "PASS: unauthenticated gh pr merge 139 exits 2 requesting MERGE_OK=139"
else
  echo "FAIL: unauthenticated gh pr merge 139 (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# 3. MERGE_OK=139 gh pr merge 139 --squash exits 0
out=$(run_hook "MERGE_OK=139 gh pr merge 139 --squash" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: matching MERGE_OK=139 exits 0"
else
  echo "FAIL: matching MERGE_OK=139 (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# MERGE_OK=12 gh pr merge 139 exits 2 with stderr containing it names 12
err=$(run_hook "MERGE_OK=12 gh pr merge 139" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'it names 12' <<<"$err"; then
  echo "PASS: mismatched token exits 2 noting it names 12"
else
  echo "FAIL: mismatched token (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# 4. MERGE_OK=139 gh pr merge https://github.com/a/b/pull/139 --auto exits 0; same URL without token exits 2
out=$(run_hook "MERGE_OK=139 gh pr merge https://github.com/a/b/pull/139 --auto" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: PR URL with matching token exits 0"
else
  echo "FAIL: PR URL with matching token (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

err=$(run_hook "gh pr merge https://github.com/a/b/pull/139 --auto" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'MERGE_OK=139' <<<"$err"; then
  echo "PASS: PR URL without token exits 2 requesting MERGE_OK=139"
else
  echo "FAIL: PR URL without token (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# 5. gh pr merge --squash (current branch, no number) exits 2
err=$(run_hook "gh pr merge --squash" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "PASS: current branch merge without token exits 2"
else
  echo "FAIL: current branch merge without token (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# MERGE_OK=any gh pr merge --squash exits 0
out=$(run_hook "MERGE_OK=any gh pr merge --squash" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: current branch merge with MERGE_OK=any exits 0"
else
  echo "FAIL: current branch merge with MERGE_OK=any (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# 6. gh api -X PUT repos/a/b/pulls/7/merge exits 2
err=$(run_hook "gh api -X PUT repos/a/b/pulls/7/merge" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'MERGE_OK=7' <<<"$err"; then
  echo "PASS: gh api merge without token exits 2"
else
  echo "FAIL: gh api merge without token (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# MERGE_OK=7 gh api -X PUT repos/a/b/pulls/7/merge exits 0
out=$(run_hook "MERGE_OK=7 gh api -X PUT repos/a/b/pulls/7/merge" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: gh api merge with MERGE_OK=7 exits 0"
else
  echo "FAIL: gh api merge with MERGE_OK=7 (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# 7. cd repo && MERGE_OK=139 gh pr merge 139 exits 0 (token earlier in command)
out=$(run_hook "cd repo && MERGE_OK=139 gh pr merge 139" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: token earlier in command exits 0"
else
  echo "FAIL: token earlier in command (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# 8. gh pr view 139, heredoc body of gh issue comment, and echo "gh pr merge 139" exit 0
out=$(run_hook "gh pr view 139" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: gh pr view 139 exits 0"
else
  echo "FAIL: gh pr view 139 (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

heredoc_cmd=$(cat <<'EOF'
gh issue comment 5 --body-file - <<'BODY'
gh pr merge 139
BODY
EOF
)
out=$(run_hook "$heredoc_cmd" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: gh pr merge inside heredoc body exits 0"
else
  echo "FAIL: gh pr merge inside heredoc (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

out=$(run_hook 'echo "gh pr merge 139"' 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: echo gh pr merge 139 exits 0"
else
  echo "FAIL: echo gh pr merge (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all merge-gate hook tests passed"
exit "$fails"
