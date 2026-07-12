#!/bin/bash
# claude-kit bootstrap for a new machine. Idempotent. Requires: jq, git, gh (authed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
mkdir -p "$CLAUDE"

echo "→ CLAUDE.md"
if [ -f "$CLAUDE/CLAUDE.md" ] && ! cmp -s "$HERE/CLAUDE.md" "$CLAUDE/CLAUDE.md"; then
  cp "$CLAUDE/CLAUDE.md" "$CLAUDE/CLAUDE.md.bak-$(date +%s)"
  echo "  existing CLAUDE.md backed up"
fi
cp "$HERE/CLAUDE.md" "$CLAUDE/CLAUDE.md"

echo "→ statusline"
cp "$HERE/statusline-command.sh" "$CLAUDE/statusline-command.sh"

echo "→ settings.json (deep-merge: fragment overlays existing; permissions.allow unions)"
if [ -f "$CLAUDE/settings.json" ]; then
  cp "$CLAUDE/settings.json" "$CLAUDE/settings.json.bak-$(date +%s)"
  jq -s '(.[0] * .[1])
         | .permissions.allow = ((.[0].permissions.allow // []) + (.[1].permissions.allow // []) | unique)' \
    "$CLAUDE/settings.json" "$HERE/settings.fragment.json" > /tmp/settings.merged.json
  jq -e . /tmp/settings.merged.json >/dev/null
  mv /tmp/settings.merged.json "$CLAUDE/settings.json"
else
  cp "$HERE/settings.fragment.json" "$CLAUDE/settings.json"
fi

echo "→ done. Restart Claude Code; the claude-kit marketplace + kit plugin load from settings."
echo "   Skills arrive as kit:pr-watch, kit:agy-delegate, kit:autofix, kit:code-review."
echo "   If migrating FROM a machine with loose copies in ~/.claude/skills/, run dedupe.sh next."
