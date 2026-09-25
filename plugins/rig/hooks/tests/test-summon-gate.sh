#!/bin/bash
# Tests for summon-gate.sh: a hand CodeRabbit summon needs CR_SUMMON_OK naming the PR (Sumit1993/rig#150).
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/summon-gate.sh"
FAILURES=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
check() {
  local name=$1 want=$2 cmd=$3 rc
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$HOOK" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq "$want" ] && pass "$name" || fail "$name (rc=$rc, want $want)"
}

check "bare summon blocked" 2 "gh pr comment 213 -R o/r --body '@coderabbitai review'"
check "full review blocked" 2 "gh pr comment 213 --body '@coderabbitai full review'"
check "review full form blocked" 2 "gh pr comment 213 --body '@coderabbit review full'"
check "api summon blocked" 2 "gh api repos/o/r/issues/213/comments -f body='@coderabbitai review'"
check "token naming the PR allowed" 0 "CR_SUMMON_OK=213 gh pr comment 213 --body '@coderabbitai review'"
check "token naming another PR blocked" 2 "CR_SUMMON_OK=214 gh pr comment 213 --body '@coderabbitai review'"
check "in-thread fix reply allowed" 0 "bash cr-reply.sh 213 999 '@coderabbitai Fixed in abc: x. Please verify.'"
check "reading comments allowed" 0 "gh api repos/o/r/issues/213/comments --jq '.[]|select(.body|test(\"@coderabbitai review\"))'"
check "grep in a file allowed" 0 "grep -n '@coderabbitai review' skills/x.md"
check "junk input exits 0" 0 ""
printf 'not json' | "$HOOK" >/dev/null 2>&1 && pass "non-JSON stdin exits 0" || fail "non-JSON stdin"

echo
[ "$FAILURES" -eq 0 ] && { echo "all summon-gate hook tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
