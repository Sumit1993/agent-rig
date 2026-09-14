#!/bin/bash
# Codex plugin from plugins/rig: codex-tagged skills and nine hooks (five Bash gates plus
# four ported to Codex's payload shape under #141b). hooks.json is filtered from the
# Claude file so commands never drift (#141).
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../plugins/rig" && pwd)"
OUT="${1:?usage: build-codex-plugin.sh <out-dir>}"

ALLOWED_HOOKS=(
  gh-body-stamp.sh gh-body-no-scratch.sh issue-create-nudge.sh no-broad-agy-kill.sh release-docs-gate.sh
  organizer-seat.sh subagent-no-stall.sh delegate-check.sh outside-view-nudge.sh
)

rm -rf "$OUT"
mkdir -p "$OUT/skills" "$OUT/hooks/lib" "$OUT/.codex-plugin" "$OUT/.claude-plugin"

version=$(jq -r .version "$SRC/.claude-plugin/plugin.json")
description=$(jq -r .description "$SRC/.claude-plugin/plugin.json")
jq -n --arg v "$version" --arg d "$description" \
  '{name: "rig", version: $v, description: $d}' > "$OUT/.codex-plugin/plugin.json"

for skill in "$SRC"/skills/*/SKILL.md; do
  dir=$(dirname "$skill")
  awk '/^---$/{n++; next} n==1' "$skill" | grep -qE '^[[:space:]]+harnesses:.*\bcodex\b' || continue
  cp -r "$dir" "$OUT/skills/"
done

for h in "${ALLOWED_HOOKS[@]}"; do
  cp "$SRC/hooks/$h" "$OUT/hooks/$h"
done
cp "$SRC/hooks/lib/gh-command.sh" "$SRC/hooks/lib/report-guard.sh" "$OUT/hooks/lib/"

hook_re='gh-body-stamp\.sh|gh-body-no-scratch\.sh|issue-create-nudge\.sh|no-broad-agy-kill\.sh|release-docs-gate\.sh|organizer-seat\.sh|subagent-no-stall\.sh|delegate-check\.sh|outside-view-nudge\.sh'
# Keeps PreToolUse entries matched as Bash, Edit|Write|NotebookEdit or Agent, plus
# SubagentStop. outside-view-nudge.sh's Claude matcher (AskUserQuestion|EnterPlanMode|Agent)
# names two Claude-only tools slice 1's capture never saw from Codex, so only its Agent
# alias crosses (#141).
jq --arg re "$hook_re" '
  {
    hooks: {
      PreToolUse: [
        .hooks.PreToolUse[]
        | select(.matcher == "Bash" or .matcher == "Edit|Write|NotebookEdit" or .matcher == "Agent" or .matcher == "AskUserQuestion|EnterPlanMode|Agent")
        | select(.hooks[0].command | test($re))
        | if .matcher == "AskUserQuestion|EnterPlanMode|Agent" then .matcher = "Agent" else . end
      ],
      SubagentStop: [(.hooks.SubagentStop // [])[] | select(.hooks[0].command | test($re))]
    }
  }' "$SRC/hooks/hooks.json" > "$OUT/hooks/hooks.json"

# codex plugin marketplace add reads .claude-plugin/marketplace.json, not a root file (CLI 0.154.0, #141).
jq -n \
  '{name: "rig-local", interface: {displayName: "rig (local)"}, plugins: [
    {name: "rig", source: {source: "local", path: "./"}, policy: {installation: "AVAILABLE", authentication: "ON_INSTALL"}, category: "Productivity"}
  ]}' > "$OUT/.claude-plugin/marketplace.json"

ls "$OUT/skills"
