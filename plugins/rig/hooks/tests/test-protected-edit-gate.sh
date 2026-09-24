#!/bin/bash
# Regression suite for protected-edit-gate.sh (PreToolUse Edit|Write|NotebookEdit). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/protected-edit-gate.sh"
fails=0
export PROTECTED_EDIT_HOME=$(mktemp -d)
cleanup() { rm -rf "$PROTECTED_EDIT_HOME"; }
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
  local tool=$1 path=$2 old=${3:-} content=${4:-} new=${5:-}
  jq -n --arg t "$tool" --arg p "$path" --arg o "$old" --arg c "$content" --arg n "$new" \
    '{"tool_name": $t, "tool_input": {"file_path": $p, "old_string": $o, "new_string": $n, "content": $c}}' | "$HOOK"
}

mkdir -p "$PROTECTED_EDIT_HOME/.claude/skills/x" "$PROTECTED_EDIT_HOME/.agents/skills/x"

# 2. Edit under $HOME/.claude/skills/x/SKILL.md exits 2 with stderr containing plugins/rig/skills
err=$(run_hook "Edit" "$PROTECTED_EDIT_HOME/.claude/skills/x/SKILL.md" "foo" "" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'plugins/rig/skills' <<<"$err"; then
  echo "PASS: Edit under .claude/skills exits 2 naming plugins/rig/skills"
else
  echo "FAIL: Edit under .claude/skills (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# Same for $HOME/.agents/skills/...
err=$(run_hook "Edit" "$PROTECTED_EDIT_HOME/.agents/skills/x/SKILL.md" "foo" "" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'plugins/rig/skills' <<<"$err"; then
  echo "PASS: Edit under .agents/skills exits 2 naming plugins/rig/skills"
else
  echo "FAIL: Edit under .agents/skills (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# Write there exits 2
err=$(run_hook "Write" "$PROTECTED_EDIT_HOME/.claude/skills/x/SKILL.md" "" "content" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'plugins/rig/skills' <<<"$err"; then
  echo "PASS: Write under .claude/skills exits 2"
else
  echo "FAIL: Write under .claude/skills (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# 3. $HOME/.claude/CLAUDE.md holding @/x/AGENTS.md on line 1 and local rule below:
claude_md="$PROTECTED_EDIT_HOME/.claude/CLAUDE.md"
printf '@/x/AGENTS.md\nlocal rule\n' > "$claude_md"

# Edit with old_string containing the import exits 2
err=$(run_hook "Edit" "$claude_md" "@/x/AGENTS.md" "" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "PASS: Edit touching import line exits 2"
else
  echo "FAIL: Edit touching import line (rc=$rc)"; fails=$((fails + 1))
fi

# Edit of local rule exits 0
out=$(run_hook "Edit" "$claude_md" "local rule" "" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: Edit of local rule below import exits 0"
else
  echo "FAIL: Edit of local rule (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# Write whose content keeps the import line exits 0
out=$(run_hook "Write" "$claude_md" "" '@/x/AGENTS.md
updated rule' 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: Write keeping import line exits 0"
else
  echo "FAIL: Write keeping import line (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# Write whose content drops it exits 2
err=$(run_hook "Write" "$claude_md" "" "updated rule only" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "PASS: Write dropping import line exits 2"
else
  echo "FAIL: Write dropping import line (rc=$rc)"; fails=$((fails + 1))
fi

# Write that keeps the import only as an inactive substring exits 2
err=$(run_hook "Write" "$claude_md" "" "# was @/x/AGENTS.md
updated rule" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "PASS: Write keeping the import only as a substring exits 2"
else
  echo "FAIL: Write inactive substring (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# Edit that rewrites part of the import line exits 2
err=$(run_hook "Edit" "$claude_md" "AGENTS" "" "OTHER" 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "PASS: partial Edit of the import exits 2"
else
  echo "FAIL: partial Edit of the import (rc=$rc, err=$err)"; fails=$((fails + 1))
fi

# Edit that moves text next to the import but leaves the line intact exits 0
out=$(run_hook "Edit" "$claude_md" "local rule" "" "local rule two" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: Edit below the import exits 0"
else
  echo "FAIL: Edit below the import (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# 4. $HOME/.claude/CLAUDE.md with no @ line: any edit exits 0.
printf 'no at import here\nlocal rule\n' > "$claude_md"
out=$(run_hook "Edit" "$claude_md" "local rule" "" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: CLAUDE.md without import line allows edits"
else
  echo "FAIL: CLAUDE.md without import (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

# 5. A path elsewhere exits 0 with no output.
out=$(run_hook "Edit" "$PROTECTED_EDIT_HOME/somewhere/else.txt" "foo" "" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: path elsewhere exits 0 with no output"
else
  echo "FAIL: path elsewhere (rc=$rc, out=$out)"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo && echo "all protected-edit-gate hook tests passed"
exit "$fails"
