#!/bin/bash
# Builds the agy plugin from the Claude plugin: a root plugin.json and only the skills whose frontmatter
# says `harnesses: "claude agy"`. Hooks and agents never cross, because agy's hook contract and agent
# frontmatter differ from Claude Code's. Untagged means Claude-only. Story: rig#134.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../plugins/rig" && pwd)"
OUT="${1:?usage: build-agy-plugin.sh <out-dir>}"

rm -rf "$OUT"; mkdir -p "$OUT/skills"
jq -n --arg d "$(jq -r .description "$SRC/.claude-plugin/plugin.json")" \
  '{"$schema": "https://antigravity.google/schemas/v1/plugin.json", name: "rig", description: $d}' > "$OUT/plugin.json"

for skill in "$SRC"/skills/*/SKILL.md; do
  dir=$(dirname "$skill")
  awk '/^---$/{n++; next} n==1' "$skill" | grep -qE '^[[:space:]]+harnesses:.*\bagy\b' || continue
  cp -r "$dir" "$OUT/skills/"
done
ls "$OUT/skills"
