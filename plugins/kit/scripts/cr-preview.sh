#!/bin/bash
# cr-preview.sh — CodeRabbit CLI review of the current branch, pre-push.
# Spends the CLI counter (larger than the PR counter on young OSS repos) so the
# scarce PR-side review isn't wasted on line-level nits. On completion records a
# marker that opens the pre-push gate (hooks/pre-push-cr-gate.sh) for this
# repo+branch. Marker TTL 30 min: preview -> fix -> push inside one window
# without spending a second CLI review.
# Flags per CodeRabbit CLI 0.7.0: --agent emits structured findings
# (--prompt-only no longer exists).
set -u
KIT_META="$(dirname "$0")/kit-meta.sh"
repo=$("$KIT_META" current 2>/dev/null | jq -r '.repo // empty')
[ -n "$repo" ] || { echo "cr-preview: not in a github repo" >&2; exit 1; }
branch=$(git rev-parse --abbrev-ref HEAD)
# origin/HEAD is often unset locally; fall back to whichever of main|master exists.
base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
if [ -z "$base" ]; then
  git show-ref --verify --quiet refs/remotes/origin/main && base=main
  [ -z "$base" ] && git show-ref --verify --quiet refs/remotes/origin/master && base=master
fi
base=${base:-main}
MARK_DIR="$HOME/ai-context/state/kit/cr-preview"
mkdir -p "$MARK_DIR"
mark="$MARK_DIR/$(echo "$repo-$branch" | tr '/' '-')"

coderabbit review --agent --committed --base "$base"
rc=$?
if [ "$rc" -eq 0 ]; then
  # The marker file must stay a bare epoch: pre-push-cr-gate.sh does
  # `case "$ts" in *[!0-9]*) ts=0` and BLOCKS on anything non-numeric.
  # The reviewed SHA therefore goes in a sibling file, never appended here.
  date +%s > "$mark"
  git rev-parse HEAD > "$mark.sha" 2>/dev/null
  echo "cr-preview: review complete — push gate open for $repo@$branch (30 min)"
  # Durable evidence for the `review-evidence` merge gate. Best-effort: pre-push
  # there is usually no PR yet, so this no-ops and pr-watch Phase 1 posts it after
  # `gh pr create`. Never fail the preview over it. See prismalens/prismalens#301.
  "$(dirname "$0")/cr-evidence.sh" --quiet || true
else
  echo "cr-preview: coderabbit review exited $rc — gate NOT opened" >&2
fi
exit "$rc"
