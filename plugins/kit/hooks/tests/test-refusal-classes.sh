#!/bin/bash
# CodeRabbit refuses a trigger in two ways that mean opposite things, and the watcher
# only ever matched one of them. Bodies are REAL, from prismalens/gh-workflows#98.
# See claude-kit#28.
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHER="$SELF_DIR/../../skills/pr-watch/watch-coderabbit.sh"
FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }
[ -f "$WATCHER" ] || { echo "cannot find $WATCHER"; exit 1; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
BODYFILE="$SANDBOX/body.txt"

cat > "$SANDBOX/gh" <<STUB
#!/bin/bash
BODYFILE="$BODYFILE"
STUB
cat >> "$SANDBOX/gh" <<'STUB'
args="$*"
case "$args" in
  *"pr view"*)                 echo OPEN; exit 0 ;;
  *"pr checks"*)               exit 0 ;;
  *"contents/.coderabbit.yaml"*) echo '{"name":".coderabbit.yaml"}'; exit 0 ;;
  *"-f body="*)                echo '{}'; exit 0 ;;
  *"/pulls/"*"/comments"*)     echo '[]'; exit 0 ;;
  *"/issues/"*"/comments"*)
    jq -nc --rawfile b "$BODYFILE" \
      '[{user:{login:"coderabbitai[bot]"},created_at:"2026-01-01T00:00:00Z",updated_at:"2026-01-01T00:00:00Z",body:$b}]'
    exit 0 ;;
esac
exit 1
STUB
chmod +x "$SANDBOX/gh"
export PATH="$SANDBOX:$PATH"

# The refusal that means the head IS reviewed.
cat > "$SANDBOX/already.txt" <<'EOF'
<details>
<summary>Action not completed</summary>

Already reviewed the last commit. Use `@coderabbitai full review` to rerun a review of the entire changeset.

> Note: CodeRabbit is an incremental review system and does not re-review already reviewed commits. This command is applicable only when automatic reviews are paused.

</details>
EOF

# The reply that means the comment was parsed as conversation.
cat > "$SANDBOX/chat.txt" <<'EOF'
> [!TIP]
> For best results, initiate chat on the files or code changes.

`@someone`, understood. PR is ready for an operator to merge.
EOF

run() { # body-file -> one poll, fresh state dir
  cp "$1" "$BODYFILE"
  CR_WATCH_AUTORETRY=0 CR_WATCH_ASSUME_CODERABBIT=1 CR_WATCH_STATE_DIR="$2" \
    timeout 20 bash "$WATCHER" --repo acme/widget 7 2>&1
}

# --- "Already reviewed" settles before it fires: unchanged across two polls, then its
# own event, with the opposite meaning (claude-kit#73: the first poll must not fire on
# a body an in-place edit is about to supersede). --------------------------------
d1="$SANDBOX/s1"; mkdir -p "$d1"
out=$(run "$SANDBOX/already.txt" "$d1")
case "$out" in
  *"ALREADY REVIEWED"*) fail "already-reviewed fired on the first sighting, before it settled: $(printf '%s' "$out" | tr '\n' '|')" ;;
  *) pass "already-reviewed withheld on the first sighting" ;;
esac
out=$(run "$SANDBOX/already.txt" "$d1")
case "$out" in
  *"ALREADY REVIEWED"*"already reviewed"*) pass "an already-reviewed refusal gets its own event once settled" ;;
  *) fail "already-reviewed missed: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac
case "$out" in
  *"ANSWERED AS CHAT"*) fail "already-reviewed still misclassified as chat" ;;
  *) pass "and is not reported as a chat misparse" ;;
esac
case "$out" in
  *"full review"*) pass "and names the only command that reruns it" ;;
  *) fail "no remedy given: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac
# The old line said "no review ran", which for a merge decision is the reverse of the
# truth: this refusal is CodeRabbit asserting the head is reviewed.
case "$out" in
  *"ALREADY REVIEWED"*"No new review ran"*) pass "says no NEW review ran, not that the head is unreviewed" ;;
  *) fail "wording still reads as unreviewed: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac

# --- A genuine chat answer still reports, and no longer over-prescribes --------
d2="$SANDBOX/s2"; mkdir -p "$d2"
out=$(run "$SANDBOX/chat.txt" "$d2")
case "$out" in
  *"ANSWERED AS CHAT"*) pass "a real chat answer still fires" ;;
  *) fail "chat answer missed: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac
case "$out" in
  *"ALREADY REVIEWED"*) fail "a chat answer also fired already-reviewed" ;;
  *) pass "and does not fire already-reviewed" ;;
esac
# It fires on any chat-formatted reply, including a correct answer to a comment that was
# never a trigger. Unconditional "re-trigger with a bare comment" advice is wrong there.
case "$out" in
  *"If the comment it answered was meant as a review trigger"*) pass "chat advice is conditional, not a blanket re-trigger" ;;
  *) fail "chat advice still unconditional: $(printf '%s' "$out" | tr '\n' '|')" ;;
esac

# --- The footer every reply carries must NOT fire already-reviewed. Bodies are REAL,
# from prismalens/gh-workflows#133 and #134, reported 2026-09-06. The old matcher also
# accepted "already reviewed commits", which appears only in this Note, so it fired on
# every command reply CodeRabbit sends. See claude-kit#101. ---------------------
cat > "$SANDBOX/triggered.txt" <<'EOF'
<details>
<summary>Action performed</summary>

Review triggered.

> Note: CodeRabbit is an incremental review system and does not re-review already reviewed commits. This command is applicable only when automatic reviews are paused.

</details>
EOF

cat > "$SANDBOX/ratelimited.txt" <<'EOF'
<details>
<summary>Action not completed</summary>

Review rate limited.

> Note: CodeRabbit is an incremental review system and does not re-review already reviewed commits. This command is applicable only when automatic reviews are paused.

</details>
EOF

d3="$SANDBOX/s3"; mkdir -p "$d3"
run "$SANDBOX/triggered.txt" "$d3" >/dev/null
out=$(run "$SANDBOX/triggered.txt" "$d3")
case "$out" in
  *"ALREADY REVIEWED"*) fail "a Review-triggered reply fired already-reviewed; a review IS running: $(printf '%s' "$out" | tr '\n' '|')" ;;
  *) pass "a Review-triggered reply does not fire already-reviewed" ;;
esac

d4="$SANDBOX/s4"; mkdir -p "$d4"
run "$SANDBOX/ratelimited.txt" "$d4" >/dev/null
out=$(run "$SANDBOX/ratelimited.txt" "$d4")
case "$out" in
  *"ALREADY REVIEWED"*) fail "a rate-limited reply fired already-reviewed; the head is UNREVIEWED: $(printf '%s' "$out" | tr '\n' '|')" ;;
  *) pass "a rate-limited reply does not fire already-reviewed" ;;
esac

# --- Both dedupe on updated_at ------------------------------------------------
out=$(run "$SANDBOX/already.txt" "$d1")
case "$out" in
  *"ALREADY REVIEWED"*) fail "already-reviewed replayed on an unchanged comment" ;;
  *) pass "already-reviewed reports once per occurrence" ;;
esac

echo
[ "$FAILURES" -eq 0 ] && { echo "all refusal classification tests passed"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
