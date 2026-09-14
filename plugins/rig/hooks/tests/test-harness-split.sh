#!/bin/bash
# The agy plugin carries no Claude-only component. Refs #134.
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
fails=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

bash "$ROOT/dotfiles/build-agy-plugin.sh" "$T/agy" >/dev/null
check "plugin.json at the root, valid, named" 'jq -e ".name == \"rig\"" "$T/agy/plugin.json" >/dev/null'
check "no hooks cross to agy" '[ -z "$(find "$T/agy" -name "hooks*" -o -name "*.sh" -path "*hooks*")" ]'
check "no agents cross to agy" '[ ! -e "$T/agy/agents" ]'
check "at least one skill crosses" '[ -n "$(ls "$T/agy/skills")" ]'

# A tag is a claim; a skill that names a Claude-only tool or path cannot carry it.
bad=$(grep -rlwE 'Monitor|Workflow|SendMessage|TaskStop|ScheduleWakeup|CronCreate|subagent_type|EnterWorktree|AskUserQuestion|CLAUDE_PLUGIN_ROOT' "$T/agy/skills" 2>/dev/null)
check "no agy skill names a Claude-only tool (${bad:-none})" '[ -z "$bad" ]'

untagged=$(for s in "$ROOT"/plugins/rig/skills/*/SKILL.md; do awk '/^---$/{n++; next} n==1' "$s" | grep -q 'harnesses:.*agy' || basename "$(dirname "$s")"; done | sort)
crossed=$(ls "$T/agy/skills" | sort)
check "an untagged skill stays Claude-only" '[ -z "$(comm -12 <(echo "$untagged") <(echo "$crossed"))" ]'

if command -v agy >/dev/null 2>&1; then
  out=$(timeout 30 agy plugin validate "$T/agy" 2>&1)
  check "agy plugin validate passes" 'grep -q "\[ok\]" <<<"$out" && ! grep -qi "error" <<<"$out"'
else
  echo "SKIP: agy not installed, plugin validate not run"
fi

# Codex: codex-tagged skills, the five Bash PreToolUse gate hooks, and the four ported in
# #141b (organizer-seat, subagent-no-stall, delegate-check, outside-view-nudge) cross.
CODEX_ALLOWED_HOOKS="gh-body-no-scratch.sh gh-body-stamp.sh issue-create-nudge.sh no-broad-agy-kill.sh release-docs-gate.sh delegate-check.sh organizer-seat.sh outside-view-nudge.sh subagent-no-stall.sh"
bash "$ROOT/dotfiles/build-codex-plugin.sh" "$T/codex" >/dev/null
check ".codex-plugin/plugin.json valid, named rig" 'jq -e ".name == \"rig\"" "$T/codex/.codex-plugin/plugin.json" >/dev/null'
check "no agents cross to codex" '[ ! -e "$T/codex/agents" ]'
check "at least one skill crosses to codex" '[ -n "$(ls "$T/codex/skills")" ]'

codex_hooks=$(find "$T/codex/hooks" -maxdepth 1 -name '*.sh' -exec basename {} \; | sort)
check "every copied codex hook is in the allow list and nothing else" \
  '[ "$codex_hooks" = "$(tr " " "\n" <<<"$CODEX_ALLOWED_HOOKS" | sort)" ]'

# #141b widens this from Bash-only to the events and matchers the four ported hooks need.
check "codex hooks.json has only PreToolUse and SubagentStop entries" \
  'jq -e "(.hooks | keys | sort) == [\"PreToolUse\", \"SubagentStop\"]" "$T/codex/hooks/hooks.json" >/dev/null'
check "codex PreToolUse matchers are restricted to Bash, Edit|Write|NotebookEdit, Agent" \
  'jq -e "(.hooks.PreToolUse | all(.matcher == \"Bash\" or .matcher == \"Edit|Write|NotebookEdit\" or .matcher == \"Agent\"))" "$T/codex/hooks/hooks.json" >/dev/null'

bad_codex=$(grep -rlwE 'Monitor|Workflow|SendMessage|TaskStop|ScheduleWakeup|CronCreate|subagent_type|EnterWorktree|AskUserQuestion|CLAUDE_PLUGIN_ROOT' "$T/codex/skills" 2>/dev/null)
check "no codex skill names a Claude-only tool (${bad_codex:-none})" '[ -z "$bad_codex" ]'

untagged_codex=$(for s in "$ROOT"/plugins/rig/skills/*/SKILL.md; do awk '/^---$/{n++; next} n==1' "$s" | grep -q 'harnesses:.*codex' || basename "$(dirname "$s")"; done | sort)
crossed_codex=$(ls "$T/codex/skills" | sort)
check "an untagged skill stays out of codex too" '[ -z "$(comm -12 <(echo "$untagged_codex") <(echo "$crossed_codex"))" ]'

[ "$fails" -eq 0 ] && echo "all harness-split tests passed"; exit "$fails"
