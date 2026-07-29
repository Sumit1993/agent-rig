#!/bin/bash
# PreToolUse(Bash) hook: gate `git push` on CodeRabbit-enabled repos behind a
# fresh CodeRabbit CLI preview (scripts/cr-preview.sh), so the scarce PR-side
# review never lands on a diff full of line-level nits the CLI would have caught.
# Enabled = kit-meta coderabbit=true (data/repo-meta.json folded with observed.json).
# Marker: ~/ai-context/state/kit/cr-preview/<owner-repo-branch>, fresh for 30 min.
# Fail-open everywhere: any resolution failure allows the push.
# Escape hatch (user-approved only): include CR_GATE=skip in the command.
set -u
in=$(cat)
# Resolve before any cd — $0 may be relative to the hook's launch cwd.
KIT_META="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/kit-meta.sh"
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
grep -qE '(^|[^[:alnum:]_-])git[[:space:]]+push' <<<"$cmd" || exit 0
grep -q 'CR_GATE=skip' <<<"$cmd" && exit 0
cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null)
[ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0
repo=$("$KIT_META" current 2>/dev/null | jq -r '.repo // empty')
[ -n "$repo" ] || exit 0
[ "$("$KIT_META" get "$repo" coderabbit 2>/dev/null)" = "true" ] || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
# Pushes of the default branch (merge fast-forwards, release automation) are not
# PR diffs — allow. origin/HEAD is often unset locally; fall back to whichever of
# origin/main|origin/master exists.
def=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
if [ -z "$def" ]; then
  git show-ref --verify --quiet refs/remotes/origin/main && def=main
  [ -z "$def" ] && git show-ref --verify --quiet refs/remotes/origin/master && def=master
fi
[ "$branch" = "${def:-main}" ] && exit 0
# Docs-only diffs (only .md/.txt changed vs the default branch) are exempt —
# spending the CLI counter on markdown wastes it, and KB repos push mostly docs.
if [ -n "$def" ] && git rev-parse --verify -q "refs/remotes/origin/$def" >/dev/null 2>&1; then
  if ! git diff --name-only "origin/$def...HEAD" 2>/dev/null | grep -qvE '\.(md|txt)$'; then
    exit 0
  fi
fi
mark="$HOME/ai-context/state/kit/cr-preview/$(echo "$repo-$branch" | tr '/' '-')"
now=$(date +%s); ts=$(cat "$mark" 2>/dev/null || echo 0)
case "$ts" in ''|*[!0-9]*) ts=0;; esac
[ $((now - ts)) -lt 1800 ] && exit 0
echo "Pre-push gate: $repo is CodeRabbit-enabled and branch '$branch' has no CLI preview in the last 30 min. Run the kit plugin's scripts/cr-preview.sh from the repo root, fix what it finds, then push — this spends the abundant CLI counter and protects the scarce PR-review counter. If the user explicitly approved pushing without a preview, include CR_GATE=skip in the push command." >&2
exit 2
