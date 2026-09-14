#!/bin/bash
# Builds the Codex plugin from the Claude plugin: a .codex-plugin/plugin.json compatibility
# manifest (Codex auto-discovers hooks/hooks.json and skills/ from there), only the skills
# tagged `harnesses` containing `codex`, and only the five Bash PreToolUse gate hooks proven
# under Codex's input shape, with hooks/lib so they still find gh-command.sh and
# report-guard.sh. hooks.json is filtered from plugins/rig/hooks/hooks.json with jq so the
# command strings never drift from the Claude file. Story: agent-rig#141.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../plugins/rig" && pwd)"
OUT="${1:?usage: build-codex-plugin.sh <out-dir>}"

ALLOWED_HOOKS=(gh-body-stamp.sh gh-body-no-scratch.sh issue-create-nudge.sh no-broad-agy-kill.sh release-docs-gate.sh)

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

hook_re='gh-body-stamp\.sh|gh-body-no-scratch\.sh|issue-create-nudge\.sh|no-broad-agy-kill\.sh|release-docs-gate\.sh'
jq --arg re "$hook_re" \
  '{hooks: {PreToolUse: [.hooks.PreToolUse[] | select(.matcher == "Bash") | select(.hooks[0].command | test($re))]}}' \
  "$SRC/hooks/hooks.json" > "$OUT/hooks/hooks.json"

# The plugin root doubles as the marketplace root, so the marketplace file sits beside the
# plugin's own .codex-plugin/, hooks/ and skills/ and points its one entry back at ".".
# `codex plugin marketplace add <out-dir>` only recognizes a manifest at .claude-plugin/marketplace.json
# (verified against the installed CLI, 0.154.0) or the portable/OpenAI locations under .agents/plugins/;
# a bare marketplace.json at the root is not a supported manifest.
jq -n \
  '{name: "rig-local", interface: {displayName: "rig (local)"}, plugins: [
    {name: "rig", source: {source: "local", path: "./"}, policy: {installation: "AVAILABLE", authentication: "ON_INSTALL"}, category: "Productivity"}
  ]}' > "$OUT/.claude-plugin/marketplace.json"

ls "$OUT/skills"
