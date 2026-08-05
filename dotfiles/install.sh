#!/bin/bash
# claude-kit bootstrap for a new machine. Idempotent. Requires: jq, git, gh (authed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
mkdir -p "$CLAUDE"

# CLAUDE.md is an IMPORT STUB, not a copy.
#
# It used to be a one-way `cp` of dotfiles/CLAUDE.md. That silently forked: the live
# file accumulated real rules for a week while the repo copy sat at its last commit,
# and the next install would have overwritten them without a word. A copy nothing
# compares is a claim nothing checks.
#
# Claude Code does not read AGENTS.md on its own, but CLAUDE.md can `@`-import it, and
# imports resolve at launch. So the body lives in the repo under version control, and
# ~/.claude/CLAUDE.md holds one import line. There is no second copy left to drift.
#
# The import points at THIS checkout, resolved absolutely. Never point it at a
# marketplace plugin-cache path — those carry a version string that changes on update.
#
# Anything the operator appends below the import line is machine-local and stays out of
# the repo, so the stub is written once and then left alone.
echo "→ CLAUDE.md (import stub → dotfiles/AGENTS.md)"
# Always resolve to the MAIN checkout, never a linked worktree. Running this from a
# worktree would pin the import to a directory that is removed on merge, and every
# session afterwards would launch with the import silently unresolved.
common="$(cd "$HERE" && git rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$common" ]; then
  src_root="$(dirname "$(cd "$HERE" && cd "$common" && pwd)")"
else
  src_root="$(cd "$HERE/.." && pwd)"
fi
if [ ! -f "$src_root/dotfiles/AGENTS.md" ]; then
  echo "  ERROR: no AGENTS.md at $src_root/dotfiles — the main checkout is behind this branch." >&2
  echo "  Merge first, then re-run; a stub pointing at a missing file breaks every session." >&2
  exit 1
fi
stub="@$src_root/dotfiles/AGENTS.md"
if [ -f "$CLAUDE/CLAUDE.md" ] && grep -qxF "$stub" "$CLAUDE/CLAUDE.md"; then
  echo "  import already present — local additions left untouched"
else
  if [ -f "$CLAUDE/CLAUDE.md" ]; then
    cp "$CLAUDE/CLAUDE.md" "$CLAUDE/CLAUDE.md.bak-$(date +%s)"
    echo "  existing CLAUDE.md backed up (its content now lives in dotfiles/AGENTS.md)"
  fi
  printf '%s\n\nEdit the imported file in the claude-kit repo, not here. Anything below this line is machine-local.\n' \
    "$stub" > "$CLAUDE/CLAUDE.md"
fi

echo "→ statusline"
cp "$HERE/statusline-command.sh" "$CLAUDE/statusline-command.sh"

echo "→ settings.json (deep-merge: fragment overlays existing; permissions.allow unions)"
if [ -f "$CLAUDE/settings.json" ]; then
  cp "$CLAUDE/settings.json" "$CLAUDE/settings.json.bak-$(date +%s)"
  jq -s '.[0] as $cur | .[1] as $frag | ($cur * $frag)
         | .permissions.allow = (($cur.permissions.allow // []) + ($frag.permissions.allow // []) | unique)' \
    "$CLAUDE/settings.json" "$HERE/settings.fragment.json" > /tmp/settings.merged.json
  jq -e . /tmp/settings.merged.json >/dev/null
  mv /tmp/settings.merged.json "$CLAUDE/settings.json"
else
  cp "$HERE/settings.fragment.json" "$CLAUDE/settings.json"
fi

echo "→ done. Restart Claude Code; the claude-kit marketplace + kit plugin load from settings."
echo "   Skills arrive as kit:pr-watch, kit:agy-delegate, kit:autofix, kit:code-review."
echo "   If migrating FROM a machine with loose copies in ~/.claude/skills/, run dedupe.sh next."
