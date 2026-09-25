#!/bin/bash
# Regression suite: the five Bash PreToolUse gate hooks under Codex's own PreToolUse payload
# shape (session_id, transcript_path: null, cwd, hook_event_name, model, permission_mode,
# turn_id, tool_name: "Bash", tool_use_id, tool_input.command) rather than Claude's, asserting
# the same exit codes the Claude-shaped suites expect. Refs #141.
set -u
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
CWD=$(mktemp -d)
export ISSUE_NUDGE_STATE_DIR=$(mktemp -d)
cleanup() { rm -rf "$CWD" "$ISSUE_NUDGE_STATE_DIR"; }
trap cleanup EXIT

payload() { # <cwd> <cmd>
  jq -n --arg cwd "$1" --arg cmd "$2" '{
    session_id: "codex-sess-1",
    transcript_path: null,
    cwd: $cwd,
    hook_event_name: "PreToolUse",
    model: "gpt-5-codex",
    permission_mode: "default",
    turn_id: "turn-1",
    tool_name: "Bash",
    tool_use_id: "call-1",
    tool_input: {command: $cmd}
  }'
}

check() { # name hook want_rc cmd
  local name=$1 hook=$2 want=$3 cmd=$4 got
  payload "$CWD" "$cmd" | "$HOOKS_DIR/$hook" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got)"; fails=$((fails + 1))
  fi
}

# Every hook must accept the Codex field set and stay a no-op on an unrelated command.
for h in gh-body-stamp.sh gh-body-no-scratch.sh issue-create-nudge.sh no-broad-agy-kill.sh release-docs-gate.sh; do
  check "$h passes a plain ls under the Codex payload shape" "$h" 0 'ls -la'
done

check "gh-body-stamp.sh blocks an unstamped gh issue comment" gh-body-stamp.sh 2 \
  'gh issue comment 5 --body "this is a long enough body text with no marker present anywhere"'
check "gh-body-stamp.sh passes a stamped gh issue comment" gh-body-stamp.sh 0 \
  "gh issue comment 5 --body \"this is a long enough body. Posted by an agent under the operator's account.\""

check "gh-body-no-scratch.sh blocks a scratch path in the body" gh-body-no-scratch.sh 2 \
  'gh issue create --title "Issue" --body "see ~/ai-context/x.md"'

check "no-broad-agy-kill.sh blocks a name-wide agy kill" no-broad-agy-kill.sh 2 'pkill -f agy'

# The four hooks ported in #141b, fed the real fixtures captured from a live codex exec run.
FIXTURES="$HOOKS_DIR/tests/fixtures/codex"

check_stdin() { # name hook want_rc payload_file [extra_env=]
  local name=$1 hook=$2 want=$3 file=$4 env_kv=${5:-} got
  env $env_kv "$HOOKS_DIR/$hook" < "$file" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got)"; fails=$((fails + 1))
  fi
}

# delegate-check.sh: Codex's spawn_agent sends only tool_input.message.
check_stdin "delegate-check.sh refuses a bounded mechanical spawn_agent" delegate-check.sh 2 \
  <(jq '.tool_input.message = "write tests for the retry parser to spec"' "$FIXTURES/pretooluse-spawn-agent.json")
check_stdin "delegate-check.sh passes a spawn_agent naming agy" delegate-check.sh 0 \
  <(jq '.tool_input.message = "write tests for the retry parser; agy quota is dry so doing this directly"' "$FIXTURES/pretooluse-spawn-agent.json")

# outside-view-nudge.sh: Codex has one generic agent shape and no subagent_type field, so
# every spawn_agent is the "uncertain" moment the nudge is for.
OUTVIEW_STATE=$(mktemp -d)
out=$(env "OUTSIDE_VIEW_STATE_DIR=$OUTVIEW_STATE" "$HOOKS_DIR/outside-view-nudge.sh" < "$FIXTURES/pretooluse-spawn-agent.json" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && grep -q "outside answer" <<<"$out"; then
  echo "PASS: outside-view-nudge.sh prints its context for a spawn_agent"
else
  echo "FAIL: outside-view-nudge.sh spawn_agent case (rc=$rc, out=${out:0:80})"; fails=$((fails + 1))
fi
rm -rf "$OUTVIEW_STATE"

# subagent-no-stall.sh: SubagentStop requires valid JSON on stdout when it exits 0.
check_stdin "subagent-no-stall.sh blocks a standing-by last_assistant_message" subagent-no-stall.sh 2 \
  "$FIXTURES/subagentstop-stall.json"
out=$("$HOOKS_DIR/subagent-no-stall.sh" < "$FIXTURES/subagentstop-clean.json" 2>/dev/null)
rc=$?
if [ "$rc" -eq 0 ] && jq -e . >/dev/null 2>&1 <<<"$out"; then
  echo "PASS: subagent-no-stall.sh prints valid JSON on a clean last_assistant_message"
else
  echo "FAIL: subagent-no-stall.sh clean case (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all codex-payload hook tests passed"
exit "$fails"
