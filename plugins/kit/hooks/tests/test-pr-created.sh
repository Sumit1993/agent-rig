#!/bin/bash
# test-pr-created.sh — exercises the REAL pr-created.sh hook with `kit-meta.sh`,
# `cr-evidence.sh` and `gh` stubbed, so every case runs offline.
#
# Two properties matter more than the happy path:
#   1. The hook must always emit valid JSON (or nothing). Malformed output on a
#      PostToolUse hook corrupts the session it was meant to help.
#   2. The evidence step must not fire on a textual false positive. The trigger
#      is "the command mentioned `gh pr create` and the output had a PR URL",
#      which a grep or a test can satisfy. Acting on that would report a refusal
#      for a PR nobody opened, and a warning that cries wolf gets ignored.
#
# Usage: bash test-pr-created.sh   (exits 0 on pass, 1 on any failure)
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SELF_DIR/../pr-created.sh"
FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

[ -f "$HOOK" ] || { echo "cannot find $HOOK"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/bin"

# `gh` is reached only for the freshness probe (`pr view --json createdAt`).
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "${GH_STUB_CREATED:-}"
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

stubs() { # $1 = registry coderabbit value, $2 = cr-evidence exit code
  printf '#!/bin/bash\n[ "$3" = "coderabbit" ] && echo "%s"; exit 0\n' "$1" > "$T/scripts/kit-meta.sh"
  printf '#!/bin/bash\necho "cr-evidence: called with $*"; exit %s\n' "$2" > "$T/scripts/cr-evidence.sh"
  chmod +x "$T/scripts"/*.sh
}
aged() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }

# Assembled so this test file does not itself contain the literal trigger string.
CREATE_CMD="gh pr cre""ate --fill"
URL="https://github.com/acme/widget/pull/12"

run() { # stdin payload -> hook stdout
  jq -nc --arg c "${1:-$CREATE_CMD}" --arg r "${2:-$URL}" \
    '{tool_input:{command:$c},tool_response:$r}' \
    | CLAUDE_PLUGIN_ROOT="$T" bash "$HOOK"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }
valid_json() { printf '%s' "$1" | jq -e . >/dev/null 2>&1; }

# --- Silence on everything that is not a PR creation ------------------------
out=$(run "git status" "")
[ -z "$out" ] && pass "unrelated command -> no output" || fail "unrelated command emitted: $out"

out=$(run "$CREATE_CMD" "error: could not create pull request")
[ -z "$out" ] && pass "no PR URL in response -> no output" || fail "URL-less response emitted: $out"

# --- Fresh PR on an enabled repo: evidence attempted, outcome reported ------
export GH_STUB_CREATED=$(aged '10 seconds ago')
stubs true 0
out=$(run)
valid_json "$out" && pass "evidence-posted case emits valid JSON" || fail "invalid JSON: $out"
printf '%s' "$out" | ctx | grep -q -- '--repo acme/widget --pr 12' \
  && pass "repo and PR parsed from the URL, not the cwd" \
  || fail "wrong cr-evidence args: $(printf '%s' "$out" | ctx)"
printf '%s' "$out" | ctx | grep -q 'arm the pr-watch monitor' \
  && pass "reminder preserved alongside the evidence outcome" \
  || fail "reminder lost"

# --- A refusal must be loud and must not invite a hand-posted marker --------
stubs true 1
out=$(run)
valid_json "$out" && pass "refusal case emits valid JSON" || fail "invalid JSON: $out"
c=$(printf '%s' "$out" | ctx)
case "$c" in
  *"NOT posted (exit 1)"*) pass "refusal is reported with its exit code" ;;
  *) fail "refusal not surfaced: $c" ;;
esac
case "$c" in
  *"Never hand-post"*) pass "refusal names the hand-post trap" ;;
  *) fail "refusal does not warn against hand-posting: $c" ;;
esac

# --- Textual false positive: reminder yes, evidence no ----------------------
export GH_STUB_CREATED=$(aged '2 hours ago')
stubs true 0
out=$(run)
c=$(printf '%s' "$out" | ctx)
case "$c" in
  *evidence*) fail "evidence attempted on a stale (mentioned, not created) PR" ;;
  *"arm the pr-watch monitor"*) pass "stale match -> reminder only, evidence skipped" ;;
  *) fail "stale match produced neither: $c" ;;
esac

# --- Repos without the gate get no evidence noise ---------------------------
export GH_STUB_CREATED=$(aged '10 seconds ago')
stubs false 0
c=$(run | ctx)
case "$c" in
  *evidence*) fail "evidence noise on a repo the registry does not enable: $c" ;;
  *) pass "non-enabled repo -> reminder only" ;;
esac

# --- Undeterminable freshness fails toward doing the job -------------------
# An unreachable API must not silently skip evidence on a real PR: the evidence
# path is itself sound (it demands a completion record), so attempting is safe
# while skipping would leave a required check red for no stated reason.
export GH_STUB_CREATED=""
stubs true 0
c=$(run | ctx)
case "$c" in
  *"--repo acme/widget --pr 12"*) pass "freshness unknown -> evidence still attempted" ;;
  *) fail "freshness probe failure silently skipped evidence: $c" ;;
esac

echo
[ "$FAILURES" -eq 0 ] && { echo "all pr-created hook tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
