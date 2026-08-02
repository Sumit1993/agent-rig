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

# Guard: this reviews LOCAL HEAD, but the review-evidence gate keys on the PR
# HEAD. Normally local is simply ahead — you commit, preview, then push — and
# that is fine. What is not fine is the remote having moved underneath you
# (`gh pr update-branch`, a squash, someone else's push): then the review is
# spent on a diff the gate will never key on, and the spend is unrecoverable
# because it counts against the hourly allowance either way.
# cr-evidence.sh already refuses to post evidence for a mismatched SHA, but by
# then the review is gone. Checking here costs nothing and is the difference
# between a wasted review and a clear message.
local_head=$(git rev-parse HEAD 2>/dev/null)
pr_info=$(gh pr list --repo "$repo" --head "$branch" --state open --limit 1 \
          --json number,headRefOid \
          -q 'if length > 0 then "\(.[0].number) \(.[0].headRefOid)" else empty end' 2>/dev/null)
if [ -n "${pr_info:-}" ] && [ "${CR_PREVIEW_ALLOW_DIVERGED:-0}" != "1" ]; then
  pr_num=${pr_info%% *}; pr_head=${pr_info##* }
  if [ "$pr_head" != "$local_head" ]; then
    # Make sure we actually have the PR head object before judging ancestry;
    # without it `merge-base` errors and we would refuse a perfectly good review.
    git cat-file -e "${pr_head}^{commit}" 2>/dev/null || git fetch -q origin "$branch" 2>/dev/null
    if git cat-file -e "${pr_head}^{commit}" 2>/dev/null &&
       git merge-base --is-ancestor "$pr_head" "$local_head" 2>/dev/null; then
      : # local is ahead of the PR head — the normal pre-push case
    else
      cat >&2 <<EOM
cr-preview: refusing to spend a review — local HEAD is not ahead of the PR head.
  local HEAD    ${local_head:0:8}
  PR #$pr_num head  ${pr_head:0:8}
The remote branch moved (gh pr update-branch, a squash, or another push), so this
review would be spent on a diff the gate will not key on. Sync first:
  git fetch origin $branch && git reset --hard origin/$branch
Override with CR_PREVIEW_ALLOW_DIVERGED=1 if reviewing local-only work is intended.
EOM
      exit 1
    fi
  fi
fi

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
