#!/bin/bash
# Guards must still block when jq is absent.
#
# Every jq-reading hook answers an unreadable payload with exit 0, so for the
# four days this machine carried no jq at all, each guard passed everything it
# exists to block. Nothing failed loudly: the guard was not degraded, it was
# inverted. .coderabbit.yaml already asks reviewers to flag a missing binary
# that could change a hook's exit code, and the bug survived that instruction,
# so the question is asked here as a runnable assertion instead.
#
# PATH carries python3 but no jq, which is the fallback's whole job. The
# separate no-parser case is asserted last, where exit 0 is correct because
# "malformed input never blocks" is doctrine.
#
# no-broad-agy-kill is deliberately not fixtured here: a payload exercising it
# has to carry a broad kill pattern, and writing one trips that same guard in
# the session authoring the test. Covered by test-no-broad-agy-kill.sh instead.
set -u
cd "$(dirname "$0")/.." || exit 1
HOOKS="$(pwd)"
fails=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A PATH with python3 and no jq. The shim dir is first so a jq installed
# anywhere else cannot leak in.
mkdir -p "$TMP/bin" "$TMP/empty"
NOJQ_PATH="$TMP/bin:/usr/bin:/bin"
if PATH="$NOJQ_PATH" command -v jq >/dev/null 2>&1; then
  fail "fixture broken: jq is reachable on the no-jq PATH"
fi
if ! PATH="$NOJQ_PATH" command -v python3 >/dev/null 2>&1; then
  echo "SKIP: no python3 on $NOJQ_PATH; the fallback cannot be exercised here"
  exit 0
fi

HOOK="$HOOKS/no-haiku.sh"
[ -x "$HOOK" ] || { echo "FAIL: no-haiku.sh not executable"; exit 1; }

blocked='{"tool_name":"Agent","tool_input":{"model":"claude-haiku-4-5-20251001"}}'
allowed='{"tool_name":"Agent","tool_input":{"model":"claude-opus-5"}}'

rc=0
err=$(printf '%s' "$blocked" | PATH="$NOJQ_PATH" "$HOOK" 2>&1 >/dev/null) || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "no-haiku.sh blocks with exit 2 when jq is absent"
else
  fail "no-haiku.sh exited $rc, wanted 2, with jq absent (fail-open). stderr: ${err:-<empty>}"
fi

if grep -q '^mage:rig/guard/no-haiku$' <<<"$err"; then
  pass "the guard id still reaches stderr without jq"
else
  fail "no guard id on stderr without jq: ${err:-<empty>}"
fi

# The fallback is a second reader of the same document, never a second policy.
rc2=0
printf '%s' "$blocked" | "$HOOK" >/dev/null 2>&1 || rc2=$?
if [ "$rc2" -eq "$rc" ]; then
  pass "no-haiku.sh agrees with and without jq"
else
  fail "no-haiku.sh exited $rc without jq but $rc2 with it"
fi

# A permitted payload stays permitted, so the fallback is not simply blocking
# everything it cannot read.
rc=0
printf '%s' "$allowed" | PATH="$NOJQ_PATH" "$HOOK" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "no-haiku.sh still allows a permitted model when jq is absent"
else
  fail "no-haiku.sh exited $rc on a permitted model with jq absent"
fi

# A payload too large for one environment entry. The fallback used to carry the
# document in RIG_DOC, which caps near 128 KiB on Linux, so python3 never
# started, json_get returned 1, and the guard exited 0 on exactly the payload
# big enough to hide something. Found by review on #144.
big=$(printf 'x%.0s' $(seq 1 200000))
rc=0
err=$(printf '{"tool_name":"Agent","tool_input":{"model":"claude-haiku-4-5-20251001","pad":"%s"}}' "$big" \
  | PATH="$NOJQ_PATH" "$HOOK" 2>&1 >/dev/null) || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "no-haiku.sh blocks a 200 KB payload with jq absent"
else
  fail "no-haiku.sh exited $rc on a 200 KB payload with jq absent; the env-size bypass is back. stderr: ${err:-<empty>}"
fi

# jq and the fallback must still agree at that size.
rc2=0
printf '{"tool_name":"Agent","tool_input":{"model":"claude-haiku-4-5-20251001","pad":"%s"}}' "$big" \
  | "$HOOK" >/dev/null 2>&1 || rc2=$?
if [ "$rc2" -eq "$rc" ]; then
  pass "no-haiku.sh agrees with and without jq on a 200 KB payload"
else
  fail "200 KB payload: exited $rc without jq but $rc2 with it"
fi

# A JSON false must read as unresolved in both parsers, the way jq's // does.
got_py=$(PATH="$NOJQ_PATH" bash -c '. "$1"/lib/json.sh; json_get "{\"session_id\":false}" nosession .session_id' _ "$HOOKS" 2>/dev/null)
got_jq=$(bash -c '. "$1"/lib/json.sh; json_get "{\"session_id\":false}" nosession .session_id' _ "$HOOKS" 2>/dev/null)
if [ "$got_py" = "$got_jq" ] && [ "$got_py" = "nosession" ]; then
  pass "a JSON false falls back to the default in both parsers"
else
  fail "false handling differs: jq=[$got_jq] python3=[$got_py], wanted [nosession] from both"
fi

# Neither parser: never a crash under set -u. Exit 0 is correct, because
# unreadable input never blocking is doctrine the other suites assert.
rc=0
printf '%s' "$blocked" | PATH="$TMP/empty" "$HOOK" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
  pass "no-haiku.sh exits cleanly ($rc) with neither jq nor python3"
else
  fail "no-haiku.sh exited $rc with no parser; wanted 0 or 2, never a crash"
fi

[ "$fails" -eq 0 ] && echo && echo "all no-jq guard tests passed"
exit "$fails"
