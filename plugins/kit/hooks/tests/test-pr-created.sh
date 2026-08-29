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

# each run gets a scratch state dir unless the caller pins one, so the
# once-per-PR dedupe does not leak between cases
run() { # stdin payload -> hook stdout
  jq -nc --arg c "${1-$CREATE_CMD}" --arg r "${2-$URL}" \
    '{tool_input:{command:$c},tool_response:$r}' \
    | PR_WATCH_STATE_DIR="${3:-$(mktemp -d)}" bash "$HOOK"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }
valid_json() { printf '%s' "$1" | jq -e . >/dev/null 2>&1; }

# --- Silence unless a PR URL is actually in the output ----------------------
out=$(run "git status" "")
[ -z "$out" ] && pass "no PR URL anywhere -> no output" || fail "URL-less call emitted: $out"

out=$(run "gh pr merge 12 --squash" "$URL")
[ -z "$out" ] && pass "merge command -> no output" || fail "merge emitted: $out"

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

# --- A PR that did not come from `gh pr create` still arms ------------------
out=$(run "agy run --task raise-pr" "created $URL")
valid_json "$out" && pass "PR URL from a delegated lane emits valid JSON" || fail "delegated lane missed: $out"
c=$(printf '%s' "$out" | ctx)
case "$c" in
  *"PR #12"*"$URL"*"arm the pr-watch monitor"*) pass "delegated lane gets the same reminder as a direct create" ;;
  *) fail "delegated lane reminder differs: $c" ;;
esac

# --- Several PRs in one output all get reminded -----------------------------
URL2="https://github.com/acme/widget/pull/13"
c=$(run "bash raise-all.sh" "made $URL and $URL2" | ctx)
case "$c" in
  *"PR #12"*) case "$c" in *"PR #13"*) pass "every new PR URL in one output is reminded" ;;
              *) fail "second PR dropped: $c" ;; esac ;;
  *) fail "first PR dropped: $c" ;;
esac

# --- One reminder per PR, ever ---------------------------------------------
shared=$(mktemp -d)
first=$(run "$CREATE_CMD" "$URL" "$shared")
second=$(run "gh pr view 12" "$URL" "$shared")
[ -n "$first" ] && [ -z "$second" ] && pass "deduped: same PR reminds once" \
  || fail "dedupe broken (first=${first:0:40} second=${second:0:40})"

echo
[ "$FAILURES" -eq 0 ] && { echo "all pr-created hook tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
