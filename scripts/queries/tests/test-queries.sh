#!/bin/bash
# Regression suite for scripts/queries DuckDB SQL suite. Refs agent-rig#91, #130.
set -u

if ! command -v duckdb >/dev/null 2>&1; then
  echo "SKIP: duckdb not installed"
  exit 0
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SH="$DIR/../run.sh"
PROJECTS="$DIR/fixtures/projects"
AGY_LOGS="$DIR/fixtures/agy-logs"
export PROJECTS AGY_LOGS

fails=0
check() {
  if [ "$2" = "0" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    fails=$((fails + 1))
  fi
}

# 1-4. session-resume assertions over fixture in folder starting with '-'
sr_out=$(bash "$RUN_SH" session-resume session-fixture-123 2>&1)
sr_rc=$?

# 4. File under '-' folder is found
if [ $sr_rc -eq 0 ] && [ -n "$sr_out" ]; then
  check "fixture folder starting with '-' is found" 0
else
  check "fixture folder starting with '-' is found" 1
fi

# 1. Queued operator message appears as operator
if echo "$sr_out" | grep -E '08:20:[0-9]{2}' | grep -q 'operator.*Queued human operator message'; then
  check "queued operator message appears as operator" 0
else
  check "queued operator message appears as operator" 1
fi

# 2. Failed agent shows failed
if echo "$sr_out" | grep -q 'agent.*-> failed:'; then
  check "failed agent shows failed" 0
else
  check "failed agent shows failed" 1
fi

# 3. Tail block names errored command
if echo "$sr_out" | grep -q 'Bash.*failing-command --flag'; then
  check "tail block names errored command" 0
else
  check "tail block names errored command" 1
fi

# 5. haiku-turns counts 1
ht_out=$(bash "$RUN_SH" haiku-turns 2>&1)
if echo "$ht_out" | grep -E '│ +1 +│ +1 +│' >/dev/null 2>&1; then
  check "haiku-turns counts 1 turn" 0
else
  check "haiku-turns counts 1 turn" 1
fi

# 6. organizer-edits counts 2 edits while live: the completed-agent edit, plus an edit
# after an Agent with neither a notification nor a tool_result, live until the last
# timestamp in its own session file (agent-rig#140, 4006888937).
oe_out=$(bash "$RUN_SH" organizer-edits 2>&1)
if echo "$oe_out" | grep -E '│ +2 +│ +2 +│ +100\.0 +│' >/dev/null 2>&1; then
  check "organizer-edits counts 2 edits while live" 0
else
  check "organizer-edits counts 2 edits while live" 1
fi

# 7. reads-per-agent includes a subagent with zero Read calls in the agent set, not just
# subagent transcripts that used Read (agent-rig#140, 4006888946). Two subagent
# transcripts: agent-1 (2 reads), agent-2 (0 reads) -> agent_count=2, median_reads=1.0.
rpa_out=$(bash "$RUN_SH" reads-per-agent 2>&1)
if echo "$rpa_out" | grep -E '│ +2 +│ +1\.0 +│' >/dev/null 2>&1; then
  check "reads-per-agent counts 2 agents including the one with zero reads" 0
else
  check "reads-per-agent counts 2 agents including the one with zero reads" 1
fi

# 8. agy-dispatch-cost counts 1 run for fixture model
adc_out=$(bash "$RUN_SH" agy-dispatch-cost 2>&1)
if echo "$adc_out" | grep -E 'synthetic-fixture-model.*│ +1 +│' >/dev/null 2>&1; then
  check "agy-dispatch-cost counts 1 run for fixture model" 0
else
  check "agy-dispatch-cost counts 1 run for fixture model" 1
fi

# 9. hook-blocks counts exactly 1 real refusal for rig/guard/test-fixture, and does not
# also count the Read whose file content merely mentions that guard id (agent-rig#91).
hb_out=$(bash "$RUN_SH" hook-blocks 2>&1)
guard_hits=$(echo "$hb_out" | grep -c 'rig/guard/test-fixture' || true)
if [ "$guard_hits" -eq 1 ] && echo "$hb_out" | grep -E 'rig/guard/test-fixture *│ +Bash +│ +1 +│' >/dev/null 2>&1; then
  check "hook-blocks counts exactly 1 refusal for rig/guard/test-fixture" 0
else
  check "hook-blocks counts exactly 1 refusal for rig/guard/test-fixture" 1
fi

# 10. hook-blocks counts a refusal whose content is an array of text blocks
# (content[0].text), not just the plain-string shape (agent-rig#140, 4006888932).
if echo "$hb_out" | grep -E 'rig/guard/test-array-fixture *│ +Bash +│ +1 +│' >/dev/null 2>&1; then
  check "hook-blocks counts an array-content refusal for rig/guard/test-array-fixture" 0
else
  check "hook-blocks counts an array-content refusal for rig/guard/test-array-fixture" 1
fi

[ "$fails" -eq 0 ] && echo "all query tests passed"
exit "$fails"
