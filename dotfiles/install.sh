#!/bin/bash
# rig bootstrap for a new machine. Idempotent. Requires: jq, git, gh (authed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
mkdir -p "$CLAUDE"

# CLAUDE.md is an IMPORT STUB, not a copy.
#
# A one-way `cp` of dotfiles/CLAUDE.md would silently fork: the live file could accumulate
# real rules while the repo copy sits at an old commit, and the next install would
# overwrite them without a word. A copy nothing compares is a claim nothing checks.
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
    # Replacing a body with a stub discards whatever the body held. When that body is
    # byte-identical to AGENTS.md it is pure migration and nothing is lost. When it is
    # NOT, the difference is machine-local content this script cannot carry over — and
    # dropping it silently would be the same failure the stub exists to end. So say so,
    # loudly, and hand over the exact command to see what differed.
    bak="$CLAUDE/CLAUDE.md.bak-$(date +%s)"
    cp "$CLAUDE/CLAUDE.md" "$bak"
    if cmp -s "$CLAUDE/CLAUDE.md" "$src_root/dotfiles/AGENTS.md"; then
      echo "  existing CLAUDE.md matched AGENTS.md exactly — migrated to the import"
      echo "  backup: $bak"
    else
      echo "  WARNING: existing CLAUDE.md DIFFERS from dotfiles/AGENTS.md." >&2
      echo "  Anything in it that is not in the repo is machine-local and is NOT carried over." >&2
      echo "  backup:  $bak" >&2
      echo "  compare: diff \"$bak\" \"$src_root/dotfiles/AGENTS.md\"" >&2
      echo "  Re-add anything you still want BELOW the import line." >&2
    fi
  fi
  printf '%s\n\nEdit the imported file in the rig repo, not here. Anything below this line is machine-local.\n' \
    "$stub" > "$CLAUDE/CLAUDE.md"
fi

echo "→ statusline"
cp "$HERE/statusline-command.sh" "$CLAUDE/statusline-command.sh"

AGY="$HOME/.gemini/antigravity-cli"
if [ -d "$AGY" ]; then
  echo "→ agy statusline"
  cp "$HERE/agy-statusline-command.sh" "$AGY/statusline.sh"; chmod +x "$AGY/statusline.sh"
  s="$AGY/settings.json"; [ -f "$s" ] || echo '{}' > "$s"
  jq --arg cmd "$AGY/statusline.sh" '.statusLine = ((.statusLine // {}) + {type: "command", command: $cmd, enabled: true})' "$s" > "$s.tmp" \
    && jq -e . "$s.tmp" >/dev/null && mv "$s.tmp" "$s"
  if command -v agy >/dev/null 2>&1; then
    echo "→ agy plugin (skills tagged harnesses: claude agy; no hooks, no agents)"
    b="${XDG_DATA_HOME:-$HOME/.local/share}/rig/agy-plugin"
    bash "$HERE/build-agy-plugin.sh" "$b" >/dev/null && agy plugin install "$b"
  fi
fi

if command -v codex >/dev/null 2>&1; then
  echo "→ codex plugin (skills tagged codex; hooks proven under Codex; see build-codex-plugin.sh)"
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  mkdir -p "$codex_home"  # marketplace add fails on a machine with no CODEX_HOME yet (#141)
  cb="${XDG_DATA_HOME:-$HOME/.local/share}/rig/codex-plugin"
  bash "$HERE/build-codex-plugin.sh" "$cb" >/dev/null
  codex plugin marketplace add "$cb" >/dev/null 2>&1 || echo "  WARN: codex plugin marketplace add $cb failed" >&2
  codex plugin add rig@rig-local >/dev/null 2>&1 || echo "  WARN: codex plugin add rig@rig-local failed" >&2
  echo "  open /hooks in Codex once to review and trust the rig hooks before they run."
  # Codex reads AGENTS.md whole, with no @-import, so a symlink rather than CLAUDE.md's stub (#141).
  if [ -L "$codex_home/AGENTS.md" ]; then
    echo "→ $codex_home/AGENTS.md already a symlink, left as is"
  elif [ -e "$codex_home/AGENTS.md" ]; then
    echo "→ $codex_home/AGENTS.md is a regular file, left untouched"
  else
    ln -s "$src_root/dotfiles/AGENTS.md" "$codex_home/AGENTS.md" && echo "→ $codex_home/AGENTS.md -> dotfiles/AGENTS.md"
  fi
fi

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

echo "→ done. Restart Claude Code; the rig marketplace + rig plugin load from settings."
echo "   Skills arrive under the rig: prefix, one per directory in plugins/rig/skills/."
echo "   If migrating FROM a machine with loose copies in ~/.claude/skills/, run dedupe.sh next."
