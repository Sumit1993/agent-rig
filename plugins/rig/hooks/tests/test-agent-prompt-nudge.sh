#!/bin/bash
# Regression suite for agent-prompt-nudge.sh (PreToolUse Agent). Refs #123, #79.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/agent-prompt-nudge.sh"
fails=0
export AGENT_PROMPT_NUDGE_STATE_DIR=$(mktemp -d)
cleanup() { rm -rf "$AGENT_PROMPT_NUDGE_STATE_DIR"; }
trap cleanup EXIT

# 1. Proves printf 'x' and printf '{}' exit 0 with no output.
out=$(printf 'x' | "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: malformed stdin exits 0 with no output"
else
  echo "FAIL: malformed stdin (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

out=$(printf '{}' | "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: empty payload exits 0 with no output"
else
  echo "FAIL: empty payload (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

run_hook() {
  local session=$1 tool=$2 model=$3 st=$4 prompt=$5
  jq -n --arg s "$session" --arg t "$tool" --arg m "$model" --arg st "$st" --arg p "$prompt" \
    '{"session_id": $s, "tool_name": $t, "tool_input": {"model": $m, "subagent_type": $st, "prompt": $p}}' | "$HOOK"
}

# 2. model opus, prompt containing double-check: nudge contains double-check.
out=$(run_hook "sess_opus" "Agent" "opus" "" "please double-check the results")
rc=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if [ "$rc" -eq 0 ] && grep -q 'double-check' <<<"$ctx"; then
  echo "PASS: opus with double-check prints double-check nudge"
else
  echo "FAIL: opus double-check (rc=$rc, ctx=$ctx)"; fails=$((fails + 1))
fi

# Same for fable
out=$(run_hook "sess_fable" "Agent" "fable" "" "please double-check this")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -q 'double-check' <<<"$ctx"; then
  echo "PASS: fable with double-check prints double-check nudge"
else
  echo "FAIL: fable double-check (ctx=$ctx)"; fails=$((fails + 1))
fi

# Same for subagent_type: rig:fable-planner with echo your reasoning
out=$(run_hook "sess_fp_echo" "Agent" "" "rig:fable-planner" "echo your reasoning and verify")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -q 'double-check' <<<"$ctx"; then
  echo "PASS: fable-planner with echo your reasoning prints doublecheck nudge"
else
  echo "FAIL: fable-planner echo reasoning (ctx=$ctx)"; fails=$((fails + 1))
fi

# Model sonnet with double-check prints nothing (when verification is present).
out=$(run_hook "sess_sonnet_dc" "Agent" "sonnet" "" "double-check and verify the output")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if ! grep -q 'double-check' <<<"$ctx"; then
  echo "PASS: sonnet with double-check does not trigger doublecheck nudge"
else
  echo "FAIL: sonnet doublecheck triggered (ctx=$ctx)"; fails=$((fails + 1))
fi

# 3. Model sonnet, prompt rename things: nudge contains verification.
out=$(run_hook "sess_sonnet_raw" "Agent" "sonnet" "" "rename things")
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
if grep -qi 'verification' <<<"$ctx"; then
  echo "PASS: sonnet unverified prompt prints verification nudge"
else
  echo "FAIL: sonnet unverified prompt (ctx=$ctx)"; fails=$((fails + 1))
fi

# Prompt containing paste raw output or run the tests prints nothing.
out=$(run_hook "sess_sonnet_paste" "Agent" "sonnet" "" "rename things and paste raw output")
if [ -z "$out" ]; then
  echo "PASS: sonnet with paste raw output prints nothing"
else
  echo "FAIL: sonnet paste raw output printed: $out"; fails=$((fails + 1))
fi

out=$(run_hook "sess_sonnet_tests" "Agent" "sonnet" "" "rename things and run the tests")
if [ -z "$out" ]; then
  echo "PASS: sonnet with run the tests prints nothing"
else
  echo "FAIL: sonnet run the tests printed: $out"; fails=$((fails + 1))
fi

# 4. First fable-planner spawn prints nothing; a second in same session prints nudge containing SendMessage.
out1=$(run_hook "sess_plan" "Agent" "" "rig:fable-planner" "plan the task and verify")
out2=$(run_hook "sess_plan" "Agent" "" "rig:fable-planner" "plan next step and verify")
ctx2=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out2" 2>/dev/null)
if [ -z "$out1" ] && grep -q 'SendMessage' <<<"$ctx2"; then
  echo "PASS: second fable-planner within hour prints SendMessage nudge"
else
  echo "FAIL: second fable-planner (out1=$out1, ctx2=$ctx2)"; fails=$((fails + 1))
fi

# Write a stamp older than 3600 s into $STATE/<session>.planner-at and expect nothing.
old_time=$(( $(date +%s) - 4000 ))
echo "$old_time" > "$AGENT_PROMPT_NUDGE_STATE_DIR/sess_old.planner-at"
out=$(run_hook "sess_old" "Agent" "" "rig:fable-planner" "plan new task and verify")
if [ -z "$out" ]; then
  echo "PASS: fable-planner older than 3600s prints nothing"
else
  echo "FAIL: old fable-planner printed: $out"; fails=$((fails + 1))
fi

# 5. tool_name: spawn_agent is treated as Agent; tool_name: Bash prints nothing.
out_spawn=$(run_hook "sess_spawn" "spawn_agent" "opus" "" "please double-check")
ctx_spawn=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out_spawn" 2>/dev/null)
if grep -q 'double-check' <<<"$ctx_spawn"; then
  echo "PASS: tool_name spawn_agent treated as Agent"
else
  echo "FAIL: spawn_agent (ctx=$ctx_spawn)"; fails=$((fails + 1))
fi

out_bash=$(run_hook "sess_bash" "Bash" "opus" "" "please double-check")
if [ -z "$out_bash" ]; then
  echo "PASS: tool_name Bash prints nothing"
else
  echo "FAIL: tool_name Bash printed: $out_bash"; fails=$((fails + 1))
fi

# 6. Once per session per kind.
out_rep1=$(run_hook "sess_once_kind" "Agent" "opus" "" "please double-check")
out_rep2=$(run_hook "sess_once_kind" "Agent" "opus" "" "please double-check again")
if [ -n "$out_rep1" ] && [ -z "$out_rep2" ]; then
  echo "PASS: doublecheck nudge fires once per session"
else
  echo "FAIL: doublecheck repeated (out1=$out_rep1, out2=$out_rep2)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all agent-prompt-nudge hook tests passed"
exit "$fails"
