#!/bin/bash
# test-array-guard.sh — proves the non-array-response guard in
# watch-coderabbit.sh actually stops garbage from a transient GitHub API
# failure (a JSON *object* like {"message":"Server Error"} instead of the
# expected array) from producing phantom "NEW coderabbit" events or writing
# junk ids into the persistent seen-state file.
#
# This is not an assertion-in-prose: it extracts the real is_json_array()
# function and the real guarded comment-processing block VERBATIM out of
# watch-coderabbit.sh (by pattern, so it tracks the file if it changes),
# wraps them in a callable function, stubs `gh` on PATH, and runs it twice —
# once against a malformed object response (must be a no-op) and once
# against a well-formed array (must still work normally).
#
# Usage: bash test-array-guard.sh   (exits 0 on pass, 1 on first failure)
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/../watch-coderabbit.sh"
FAILURES=0

fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# --- Extract the real code under test, by pattern (not hardcoded line numbers) ---
is_json_array_src=$(sed -n '/^is_json_array() {$/,/^}$/p' "$SCRIPT")
block_src=$(sed -n '/^    comments_raw=\$(gh api "repos\/\$REPO\/pulls\/\$pr\/comments/,/^    fi$/p' "$SCRIPT")

[ -n "$is_json_array_src" ] || { echo "FAIL: could not extract is_json_array() from $SCRIPT — source pattern drifted"; exit 1; }
[ -n "$block_src" ] || { echo "FAIL: could not extract the guarded comment block from $SCRIPT — source pattern drifted"; exit 1; }

eval "$is_json_array_src"
eval "run_guarded_block() {
$block_src
}"

# --- Isolated sandbox: fake STATE_DIR, fake gh on PATH ---
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
STUB_BIN="$SANDBOX/bin"
mkdir -p "$STUB_BIN"
export PATH="$STUB_BIN:$PATH"

REPO="testorg/testrepo"
pr="7"
payload_dir="$SANDBOX/payload"
mkdir -p "$payload_dir"

# ============================================================
# Test 1: gh returns a JSON OBJECT (transient-error shape) —
# the guard must skip the cycle entirely: no event on stdout,
# no seen-state file mutation.
# ============================================================
seen="$SANDBOX/pr7.seen"
: > "$seen"   # pre-existing, empty seen-state (as a real re-armed watch would have)
seen_before=$(cat "$seen")

cat > "$STUB_BIN/gh" <<'EOF'
#!/bin/bash
# Stub: any `gh api .../pulls/*/comments*` call returns a malformed
# (non-array) response, mimicking a transient GitHub 5xx.
if [[ "$*" == *"pulls/"*"/comments"* ]]; then
  echo '{"message":"Server Error","documentation_url":"https://docs.github.com/rest"}'
  exit 0
fi
echo "unexpected gh stub call: $*" >&2
exit 1
EOF
chmod +x "$STUB_BIN/gh"

out=$(run_guarded_block)
seen_after=$(cat "$seen")

if [ -z "$out" ]; then
  pass "non-array response: no event emitted"
else
  fail "non-array response: expected no output, got: $out"
fi

if [ "$seen_before" = "$seen_after" ]; then
  pass "non-array response: seen-state file unchanged (still empty)"
else
  fail "non-array response: seen-state file was mutated: '$seen_after'"
fi

if [ -z "$(ls -A "$payload_dir" 2>/dev/null)" ]; then
  pass "non-array response: no payload file written"
else
  fail "non-array response: payload dir is non-empty: $(ls -A "$payload_dir")"
fi

# ============================================================
# Test 2: gh returns a well-formed ARRAY with one CodeRabbit
# comment — the guard must NOT block normal operation: the
# event fires and the id lands in seen-state.
# ============================================================
seen="$SANDBOX/pr8.seen"
: > "$seen"
payload_dir="$SANDBOX/payload8"
mkdir -p "$payload_dir"
pr="8"

cat > "$STUB_BIN/gh" <<'EOF'
#!/bin/bash
if [[ "$*" == *"pulls/8/comments"*"per_page"* ]]; then
  cat <<'JSON'
[
  {
    "id": 555,
    "path": "foo.sh",
    "line": 12,
    "original_line": 12,
    "in_reply_to_id": null,
    "user": {"login": "coderabbitai[bot]"},
    "body": "This looks off."
  }
]
JSON
  exit 0
fi
if [[ "$*" == *"pulls/comments/555"* ]]; then
  echo '{"id":555,"body":"This looks off."}'
  exit 0
fi
echo "unexpected gh stub call: $*" >&2
exit 1
EOF
chmod +x "$STUB_BIN/gh"

out=$(run_guarded_block)

if printf '%s' "$out" | grep -q "PR#8 NEW coderabbit thread — id 555"; then
  pass "well-formed array: real comment still produces an event"
else
  fail "well-formed array: expected a 'NEW coderabbit thread — id 555' event, got: $out"
fi

if grep -qx "555" "$seen"; then
  pass "well-formed array: id 555 recorded in seen-state"
else
  fail "well-formed array: seen-state does not contain 555: '$(cat "$seen")'"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "$FAILURES check(s) FAILED"
  exit 1
fi
