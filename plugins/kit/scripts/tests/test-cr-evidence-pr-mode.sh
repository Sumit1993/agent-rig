#!/bin/bash
# test-cr-evidence-pr-mode.sh — exercises `cr-evidence.sh --repo/--pr`, the mode
# the `pr-created` PostToolUse hook uses, against the REAL script.
#
# `gh` and the preview log directory are both stubbed, so every case runs offline
# and the "posts evidence" case is proved by the stub recording the call rather
# than by anything reaching GitHub.
#
# The cases that matter are the refusals: this script is the only thing standing
# between an automated caller and false evidence on a required merge gate
# (prismalens/prismalens#301 §4).
#
# Usage: bash test-cr-evidence-pr-mode.sh   (exits 0 on pass, 1 on any failure)
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/../cr-evidence.sh"
FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

[ -x "$SCRIPT" ] || { echo "cannot execute $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Stub `gh` on PATH -------------------------------------------------------
# `pr view` answers from files the test writes; `pr comment` appends to a log so
# a post can be asserted; `api` returns an empty comment list (no marker yet).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/bin/bash
# Every invocation is recorded argv-first, so the test can assert what the script
# actually addressed — a stub that answers without recording would pass even if
# the script dropped --repo and hit the wrong repository's PR 12.
printf '%s\n' "$*" >> "$GH_STUB_CALLS"
case "$1 $2" in
  "pr view")  cat "$GH_STUB_PRVIEW" ;;
  "pr comment")
      printf '%s\n' "$*" >> "$GH_STUB_POSTED"
      [ "${GH_STUB_POST_FAILS:-0}" = "1" ] && exit 1
      exit 0 ;;
  "api "*)    printf '%s' "${GH_STUB_COMMENTS:-}" ;;
  *)          exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_STUB_PRVIEW="$TMP/prview" GH_STUB_POSTED="$TMP/posted" GH_STUB_CALLS="$TMP/calls"

# --- Stub the preview-log tree the completion check reads --------------------
# cr-evidence.sh derives it from $HOME, so relocating HOME relocates the logs.
export HOME="$TMP/home"
LOGS="$HOME/ai-context/state/kit/cr-preview/logs"
mkdir -p "$LOGS"

HEAD_SHA="abc1234def5678901234567890abcdef12345678"
SHORT="abc1234"
REPO="acme/widget"
BRANCH="feat/thing"
SLUG="acme-widget-feat-thing"   # repo-branch with '/' -> '-'

write_pr () { printf '%s %s %s %s\n' "12" "$1" "$BRANCH" "$HEAD_SHA" > "$GH_STUB_PRVIEW"; }
complete_log () { printf '%s\n' \
  '{"type":"status","msg":"start"}' \
  '{"type":"complete","findings":0}' > "$LOGS/$SLUG.$SHORT.jsonl"; }
partial_log () { printf '%s\n' \
  '{"type":"status","msg":"start"}' \
  '{"type":"heartbeat"}' > "$LOGS/$SLUG.$SHORT.jsonl"; }
reset () { rm -f "$LOGS"/*.jsonl "$GH_STUB_POSTED" "$GH_STUB_CALLS"; unset GH_STUB_COMMENTS; write_pr OPEN; }

run () { "$SCRIPT" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }
posted () { [ -s "$GH_STUB_POSTED" ]; }

# --- A value flag with no value must not hang -------------------------------
# `shift 2` with one argument left fails and shifts nothing, so the parse loop
# re-reads the same flag forever. `cr-evidence.sh --sha` used to hang.
reset
for flag in --sha --repo --pr; do
  timeout 5 "$SCRIPT" "$flag" >/dev/null 2>"$TMP/err"; rc=$?
  { [ "$rc" = "2" ] && grep -q 'requires a value' "$TMP/err"; } \
    && pass "$flag with no value -> usage error, no hang" \
    || fail "$flag with no value: rc=$rc (124 = still hanging) err=$(cat "$TMP/err")"
done

# --- Argument validation: the flags are a pair ------------------------------
reset
rc=$(run --pr 12)
[ "$rc" = "2" ] && grep -q 'requires --repo' "$TMP/err" \
  && pass "--pr without --repo is a usage error" \
  || fail "--pr without --repo: rc=$rc err=$(cat "$TMP/err")"

rc=$(run --repo "$REPO")
[ "$rc" = "2" ] && grep -q 'requires --pr' "$TMP/err" \
  && pass "--repo without --pr is a usage error" \
  || fail "--repo without --pr: rc=$rc err=$(cat "$TMP/err")"

rc=$(run --repo "$REPO" --pr 12abc)
[ "$rc" = "2" ] && pass "non-numeric --pr rejected" || fail "non-numeric --pr: rc=$rc"

for bad in "widget" "/widget" "acme/widget/extra" 'acme/wid;get'; do
  rc=$(run --repo "$bad" --pr 12)
  [ "$rc" = "2" ] && pass "malformed --repo '$bad' rejected" \
    || fail "malformed --repo '$bad' accepted: rc=$rc"
done

# --- The completion record decides ------------------------------------------
reset; complete_log
rc=$(run --repo "$REPO" --pr 12)
{ [ "$rc" = "0" ] && posted; } \
  && pass "completed review for PR head -> evidence posted" \
  || fail "completed review: rc=$rc posted=$(posted && echo yes || echo no) err=$(cat "$TMP/err")"

reset; complete_log
"$SCRIPT" --repo "$REPO" --pr 12 >/dev/null 2>&1
grep -q "cr-cli-review: $HEAD_SHA" "$GH_STUB_POSTED" \
  && pass "marker vouches for the PR head sha, not a local HEAD" \
  || fail "marker sha wrong: $(cat "$GH_STUB_POSTED")"

# Every call must name the repo explicitly. Without --repo, `gh` falls back to
# whatever repo the working directory belongs to — the cwd dependency this mode
# exists to remove — and would address some other project's PR 12.
for expect in "pr view 12 --repo $REPO" "pr comment 12 --repo $REPO"; do
  grep -qF -- "$expect" "$GH_STUB_CALLS" \
    && pass "gh call targets the PR explicitly: ${expect% --repo*} --repo $REPO" \
    || fail "no gh call matching '$expect'; calls were: $(tr '\n' '|' < "$GH_STUB_CALLS")"
done
grep -q '^api repos/'"$REPO"'/issues/12/comments' "$GH_STUB_CALLS" \
  && pass "idempotency lookup reads the right repo and PR" \
  || fail "idempotency lookup wrong: $(tr '\n' '|' < "$GH_STUB_CALLS")"

reset; partial_log
rc=$(run --repo "$REPO" --pr 12)
{ [ "$rc" = "1" ] && ! posted && grep -q 'no completed CLI review' "$TMP/err"; } \
  && pass "log with no 'complete' event -> refuses, posts nothing" \
  || fail "partial log: rc=$rc posted=$(posted && echo yes || echo no)"

reset   # no log at all
rc=$(run --repo "$REPO" --pr 12)
{ [ "$rc" = "1" ] && ! posted; } \
  && pass "no preview log for that sha -> refuses, posts nothing" \
  || fail "missing log: rc=$rc posted=$(posted && echo yes || echo no)"

# A log for a DIFFERENT sha must not vouch for this head — the whole point of
# keying evidence to a commit.
reset
printf '%s\n' '{"type":"complete"}' > "$LOGS/$SLUG.9999999.jsonl"
rc=$(run --repo "$REPO" --pr 12)
{ [ "$rc" = "1" ] && ! posted; } \
  && pass "completed review for a different sha does not vouch for this head" \
  || fail "wrong-sha log accepted: rc=$rc posted=$(posted && echo yes || echo no)"

# --- Refusals survive --quiet ----------------------------------------------
reset; partial_log
rc=$(run --repo "$REPO" --pr 12 --quiet)
{ [ "$rc" = "1" ] && [ -s "$TMP/err" ]; } \
  && pass "refusal reaches stderr even with --quiet" \
  || fail "--quiet silenced the refusal: rc=$rc err=$(cat "$TMP/err")"

# --- Non-open PRs and idempotency ------------------------------------------
for state in CLOSED MERGED; do
  reset; complete_log; write_pr "$state"
  rc=$(run --repo "$REPO" --pr 12)
  { [ "$rc" = "0" ] && ! posted; } \
    && pass "$state PR -> no post, no error" \
    || fail "$state PR: rc=$rc posted=$(posted && echo yes || echo no)"
done

reset; complete_log
export GH_STUB_COMMENTS="<!-- cr-cli-review: $HEAD_SHA -->"
rc=$(run --repo "$REPO" --pr 12)
{ [ "$rc" = "0" ] && ! posted; } \
  && pass "marker already present -> idempotent, no second comment" \
  || fail "idempotency: rc=$rc posted=$(posted && echo yes || echo no)"
unset GH_STUB_COMMENTS

# --- An unreadable PR must fail closed, not fall back to the cwd -----------
reset; complete_log
: > "$GH_STUB_PRVIEW"   # `gh pr view` returns nothing
rc=$(run --repo "$REPO" --pr 12)
{ [ "$rc" = "1" ] && ! posted && grep -q 'cannot read' "$TMP/err"; } \
  && pass "unreadable PR -> refuses instead of guessing from the cwd" \
  || fail "unreadable PR: rc=$rc posted=$(posted && echo yes || echo no)"

echo
[ "$FAILURES" -eq 0 ] && { echo "all cr-evidence --pr mode tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
