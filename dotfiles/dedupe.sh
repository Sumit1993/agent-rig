#!/bin/bash
# Remove the loose ~/.claude copies that agent-rig's plugin now provides.
# Run ONCE, after the plugin is confirmed loaded (skills show as rig:pr-babysit etc.).
set -euo pipefail
CLAUDE="$HOME/.claude"
for s in pr-babysit farm-out autofix code-review; do
  [ -d "$CLAUDE/skills/$s" ] && rm -r "$CLAUDE/skills/$s" && echo "removed loose skill: $s"
done
if [ -f "$CLAUDE/hooks/pr-created.sh" ]; then
  rm "$CLAUDE/hooks/pr-created.sh" && echo "removed loose hook script"
fi
# Strip the settings.json PostToolUse entry that pointed at the loose hook (plugin hooks.json replaces it)
jq '(.hooks.PostToolUse // []) |= map(select((.hooks // []) | any(.command // "" | contains("pr-created.sh")) | not))' \
  "$CLAUDE/settings.json" > /tmp/settings.dedupe.json
jq -e . /tmp/settings.dedupe.json >/dev/null && mv /tmp/settings.dedupe.json "$CLAUDE/settings.json"
echo "settings.json hook entry removed. Restart Claude Code."
