#!/bin/bash
# test-review-debt.sh — exercises the review-debt.sh SessionStart hook offline.
#
# Usage: bash test-review-debt.sh   (exits 0 on pass, 1 on any failure)
set -u

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

REAL_GIT=$(type -p git)
cat > "$SANDBOX/git" <<STUB
#!/bin/bash
if [ -n "\${GIT_STUB_FAIL-}" ]; then
  exit 1
fi
if [ -n "\${GIT_STUB_ORIGIN-}" ]; then
  case "\$*" in
    *"remote get-url origin"*) echo "\$GIT_STUB_ORIGIN"; exit 0 ;;
  esac
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$SANDBOX/git"

cat > "$SANDBOX/gh" <<'STUB'
#!/bin/bash
if [ -n "${GH_STUB_FAIL-}" ]; then
  exit 1
fi
if [ -n "${GH_STUB_GRAPHQL-}" ]; then
  case "$*" in
    *"api graphql"*) printf '%s' "$GH_STUB_GRAPHQL"; exit 0 ;;
  esac
fi
exit 1
STUB
chmod +x "$SANDBOX/gh"
export PATH="$SANDBOX:$PATH"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SELF_DIR/../review-debt.sh"
FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

[ -f "$HOOK" ] || { echo "cannot find $HOOK"; exit 1; }

run() {
  printf '%s' "${1-{}}" | bash "$HOOK"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
valid_json() { printf '%s' "$1" | jq -e . >/dev/null 2>&1; }

GQL_TWO='{"data":{"search":{"nodes":[{"number":815,"isDraft":false,"reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":true}]}},{"number":812,"isDraft":false,"reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":false},{"isResolved":false},{"isResolved":false}]}}]}}}'
GQL_RESOLVED='{"data":{"search":{"nodes":[{"number":812,"isDraft":false,"reviewThreads":{"nodes":[{"isResolved":true},{"isResolved":true}]}}]}}}'
GQL_DRAFT='{"data":{"search":{"nodes":[{"number":820,"isDraft":true,"reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":false}]}}]}}}'

# --- Case 1: Two PRs with 4 and 1 unresolved threads -------------------------
out=$(GIT_STUB_ORIGIN="git@github.com:owner/name.git" GH_STUB_GRAPHQL="$GQL_TWO" run "{}")
rc=$?
[ "$rc" -eq 0 ] && valid_json "$out" && pass "two PRs with debt emits valid JSON" || fail "invalid JSON or exit $rc: $out"
c=$(printf '%s' "$out" | ctx)
want="Review debt in owner/name: #812 (4 open threads), #815 (1 open thread). Clear it before any new pick: compass Step 0."
if [ "$c" = "$want" ]; then
  pass "two PRs with 4 and 1 unresolved threads: exact line, ordered ascending, singular for 1"
else
  fail "unexpected output: got '$c', want '$want'"
fi

# --- Case 2: All threads resolved --------------------------------------------
out=$(GIT_STUB_ORIGIN="git@github.com:owner/name.git" GH_STUB_GRAPHQL="$GQL_RESOLVED" run "{}")
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "all threads resolved -> no output, exit 0" || fail "resolved emitted: rc=$rc out=$out"

# --- Case 3: A draft with unresolved threads only ----------------------------
out=$(GIT_STUB_ORIGIN="git@github.com:owner/name.git" GH_STUB_GRAPHQL="$GQL_DRAFT" run "{}")
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "draft with unresolved threads only -> no output, exit 0" || fail "draft emitted: rc=$rc out=$out"

# --- Case 4: gh exits non-zero -----------------------------------------------
out=$(GIT_STUB_ORIGIN="git@github.com:owner/name.git" GH_STUB_FAIL=1 run "{}")
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "gh exits non-zero -> no output, exit 0" || fail "gh failure emitted: rc=$rc out=$out"

# --- Case 5: Not a git repo --------------------------------------------------
out=$(GIT_STUB_FAIL=1 GH_STUB_GRAPHQL="$GQL_TWO" run "{}")
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "not a git repo -> no output, exit 0" || fail "not a git repo emitted: rc=$rc out=$out"

# --- Case 6: Non-github origin -----------------------------------------------
out=$(GIT_STUB_ORIGIN="git@gitlab.com:owner/name.git" GH_STUB_GRAPHQL="$GQL_TWO" run "{}")
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "non-github origin -> no output, exit 0" || fail "non-github origin emitted: rc=$rc out=$out"

# --- Malformed stdin survives ------------------------------------------------
out=$(printf 'not json' | GIT_STUB_ORIGIN="git@github.com:owner/name.git" GH_STUB_GRAPHQL="$GQL_TWO" bash "$HOOK")
rc=$?
[ "$rc" -eq 0 ] && valid_json "$out" && pass "malformed stdin survives" || fail "malformed stdin rc=$rc out=$out"

# --- More threads than one page: resolved first page still reports debt ------
GQL_MANY='{"data":{"search":{"nodes":[{"number":830,"isDraft":false,"reviewThreads":{"totalCount":150,"nodes":[{"isResolved":true}]}}]}}}'
c=$(GIT_STUB_ORIGIN="git@github.com:owner/name.git" GH_STUB_GRAPHQL="$GQL_MANY" run "{}" | ctx)
case "$c" in
  *"#830 (0+ open threads, more than 100 in total)"*) pass "unread thread pages still report debt" ;;
  *) fail "unread thread pages hidden: '$c'" ;;
esac

# --- A PR with debt on the second search page (--paginate prints one document per page) ---
GQL_PAGES='{"data":{"search":{"pageInfo":{"hasNextPage":true},"nodes":[{"number":840,"isDraft":false,"reviewThreads":{"totalCount":1,"nodes":[{"isResolved":true}]}}]}}}{"data":{"search":{"pageInfo":{"hasNextPage":false},"nodes":[{"number":941,"isDraft":false,"reviewThreads":{"totalCount":1,"nodes":[{"isResolved":false}]}}]}}}'
c=$(GIT_STUB_ORIGIN="git@github.com:owner/name.git" GH_STUB_GRAPHQL="$GQL_PAGES" run "{}" | ctx)
case "$c" in
  *"#941 (1 open thread)"*) pass "debt on a later search page is reported" ;;
  *) fail "later search page dropped: '$c'" ;;
esac

echo
[ "$FAILURES" -eq 0 ] && { echo "all review-debt hook tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
