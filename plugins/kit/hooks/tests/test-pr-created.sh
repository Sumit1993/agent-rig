#!/bin/bash
# test-pr-created.sh — exercises the REAL pr-created.sh hook offline.
#
# The property that matters more than the happy path: the hook must always emit
# valid JSON, or nothing at all. Malformed output on a PostToolUse hook corrupts
# the session it was meant to help.
#
# Usage: bash test-pr-created.sh   (exits 0 on pass, 1 on any failure)
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SELF_DIR/../pr-created.sh"
FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

[ -f "$HOOK" ] || { echo "cannot find $HOOK"; exit 1; }

# Assembled so this test file does not itself contain the literal trigger string.
CREATE_CMD="gh pr cre""ate --fill"
URL="https://github.com/acme/widget/pull/12"

run() { # stdin payload -> hook stdout
  jq -nc --arg c "${1:-$CREATE_CMD}" --arg r "${2:-$URL}" \
    '{tool_input:{command:$c},tool_response:$r}' \
    | bash "$HOOK"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }
valid_json() { printf '%s' "$1" | jq -e . >/dev/null 2>&1; }

# --- Silence on everything that is not a PR creation ------------------------
out=$(run "git status" "")
[ -z "$out" ] && pass "unrelated command -> no output" || fail "unrelated command emitted: $out"

out=$(run "$CREATE_CMD" "error: could not create pull request")
[ -z "$out" ] && pass "no PR URL in response -> no output" || fail "URL-less response emitted: $out"

# --- A raised PR produces the watch reminder --------------------------------
out=$(run)
valid_json "$out" && pass "raised PR emits valid JSON" || fail "invalid JSON: $out"
c=$(printf '%s' "$out" | ctx)
case "$c" in
  *"PR #12"*) pass "PR number parsed from the URL, not the cwd" ;;
  *) fail "wrong PR number: $c" ;;
esac
case "$c" in
  *"https://github.com/acme/widget/pull/12"*) pass "URL carried through verbatim" ;;
  *) fail "URL lost: $c" ;;
esac
case "$c" in
  *"arm the pr-watch monitor"*) pass "watch reminder present" ;;
  *) fail "reminder lost: $c" ;;
esac

echo
[ "$FAILURES" -eq 0 ] && { echo "all pr-created hook tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
