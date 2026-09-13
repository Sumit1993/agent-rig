#!/bin/bash
# test-pr-created.sh — exercises the REAL pr-created.sh hook offline.
#
# The property that matters more than the happy path: the hook must always emit
# valid JSON, or nothing at all. Malformed output on a PostToolUse hook corrupts
# the session it was meant to help.
#
# Usage: bash test-pr-created.sh   (exits 0 on pass, 1 on any failure)
set -u

# seed_seen() in the hook does a real `gh api` call and writes CR_WATCH_STATE_DIR. Without
# both of these the suite hit github.com with the user's credentials on every run and wrote
# to real state. Stub gh and redirect the dir: this suite is meant to be offline.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export CR_WATCH_STATE_DIR="$SANDBOX/cr-watch"
# The stub also stands in for the existence check the hook now does. Default: exit 1 with
# no message, which the hook reads as "could not tell" and still reminds. GH_STUB_404 makes
# it answer a definite 404 for URLs containing that string; GH_STUB_OK makes it succeed.
cat > "$SANDBOX/gh" <<'STUB'
#!/bin/bash
if [ -n "${GH_STUB_404-}" ]; then
  case "$*" in *"${GH_STUB_404}"*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;; esac
fi
if [ -n "${GH_STUB_OK-}" ]; then
  case "$*" in *"${GH_STUB_OK}"*) echo 12; exit 0 ;; esac
fi
exit 1
STUB
chmod +x "$SANDBOX/gh"
export PATH="$SANDBOX:$PATH"
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
case "$c" in
  *"/autofix-pr"*"arm the pr-watch monitor"*) pass "autofix-pr is offered first, the Monitor second" ;;
  *) fail "watcher order wrong: $c" ;;
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

# --- Agent tool results: how a delegated lane's PR actually surfaces ---------
# An agy lane redirects output to a file, so the URL never reaches a Bash result;
# it arrives in the handler subagent's report. Story: gh-workflows#69.
agent_dir=$(mktemp -d)
quiet=$(run 'agy --model gemini-3.8-flash-high -p "$(cat p.md)" > "$OUT" 2> "$OUT.err"' "" "$agent_dir")
[ -z "$quiet" ] && pass "a redirected agy launch surfaces no URL, so nothing fires" \
  || fail "fired on a launch that printed no URL: ${quiet:0:60}"

report=$(run "" "Verified 3 checks. Lane opened $URL" "$agent_dir")
case "$report" in
  *"$URL"*) pass "the handler's report is what triggers the nudge" ;;
  *) fail "handler report did not trigger: ${report:0:60}" ;;
esac

# --- Seeding has side effects, so it only runs for THIS repo -----------------
# The URL match is deliberately loose, so any file content mentioning a PR link reaches
# the hook. Seeding on that spent a real `gh api` call and wrote real state for repos
# nobody was watching; a routine `cat` of this very file did it. Reminder yes, seed no.
side=$(mktemp -d)
out=$(run "cat notes.txt" "see https://github.com/octocat/Hello-World/pull/1" "$side/p1")
case "$out" in
  *"octocat/Hello-World/pull/1"*) pass "an unrelated repo's PR still reminds" ;;
  *) fail "unrelated PR did not remind: ${out:0:60}" ;;
esac
case "$out" in
  *"seed the seen-state first"*) pass "and says the seen-state is NOT seeded" ;;
  *) fail "reminder overclaims seeding for another repo: ${out:0:80}" ;;
esac
[ -z "$(ls "$CR_WATCH_STATE_DIR" 2>/dev/null)" ] \
  && pass "an unrelated repo's PR writes no cr-watch state" \
  || fail "seeded cr-watch state for a repo we are not in: $(ls "$CR_WATCH_STATE_DIR")"
rm -rf "$side"

# --- A PR URL that is a fixture, not a PR -----------------------------------
# An agy lane seeded a mock DB row holding github.com/prismalens/gh-workflows/pull/42.
# The string reached a tool result and the hook urged a handler to arm a watcher on a PR
# that returns 404. Test output and a real PR nobody printed look identical, so the hook
# asks GitHub. Story: gh-workflows unattended run, fictional pull/42.
GHOST="https://github.com/acme/widget/pull/42"
ghost_dir=$(mktemp -d)
out=$(GH_STUB_404="pulls/42" run "cat fixtures.sql" "insert ... '$GHOST'" "$ghost_dir")
[ -z "$out" ] && pass "a 404 PR URL emits nothing" || fail "fired on a nonexistent PR: $out"
[ -z "$(ls "$ghost_dir" 2>/dev/null)" ] \
  && pass "and writes no dedupe marker, so a real #42 later still fires" \
  || fail "marked a nonexistent PR seen, suppressing the real one forever: $(ls "$ghost_dir")"
real=$(GH_STUB_OK="pulls/42" run "$CREATE_CMD" "$GHOST" "$ghost_dir" | ctx)
case "$real" in
  *"PR #42"*"confirmed to exist"*) pass "the same number, once real, fires and says it was checked" ;;
  *) fail "a real PR at a previously-404 number did not fire: ${real:0:80}" ;;
esac
rm -rf "$ghost_dir"

# --- An existence check that itself fails must not suppress ------------------
# No auth, no network, rate limit: unknown is not absent. A missed real PR costs more
# than a nudge that turns out to be a fixture, so the hook reminds and says it is unsure.
c=$(run "$CREATE_CMD" "https://github.com/acme/widget/pull/77" | ctx)
case "$c" in
  *"PR #77"*"UNVERIFIED"*) pass "an unresolvable check still reminds, marked UNVERIFIED" ;;
  *) fail "an unresolvable check suppressed or overclaimed: ${c:0:100}" ;;
esac
case "$c" in
  *"gh pr view"*) pass "and tells the session how to check it" ;;
  *) fail "UNVERIFIED reminder gives no way to check: ${c:0:120}" ;;
esac

echo
[ "$FAILURES" -eq 0 ] && { echo "all pr-created hook tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
