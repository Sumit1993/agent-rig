#!/bin/bash
# wt.sh — worktree manager enforcing ~/worktrees/<repo>/<slug>. Run inside the repo.
#   create <slug> [<base>]  add (or reuse) the worktree on branch <slug>; prints path
#   rm <slug>               remove the worktree and delete its local branch
#   prune                   list worktrees whose branch has a merged PR
#   prune --force           remove them
#   list                    git worktree list
# Merged-detection goes through `gh pr list --state merged`, not merge-base:
# squash merges leave no ancestry, and a never-pushed WIP branch must never
# count as merged.
set -eu
cmd="${1:-}"; shift || true
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "wt: not in a git repo" >&2; exit 1; }
repo=$(basename "$root")
WT_ROOT="$HOME/worktrees/$repo"

case "$cmd" in
  create)
    slug="${1:?usage: wt.sh create <slug> [<base>]}"; base="${2:-HEAD}"
    path="$WT_ROOT/$slug"
    if git worktree list --porcelain | grep -qx "worktree $path"; then
      echo "$path"
      exit 0
    fi
    mkdir -p "$WT_ROOT"
    if git show-ref --verify --quiet "refs/heads/$slug"; then
      git worktree add "$path" "$slug" >/dev/null
    else
      git worktree add -b "$slug" "$path" "$base" >/dev/null
    fi
    echo "$path";;
  rm)
    slug="${1:?usage: wt.sh rm <slug>}"
    git worktree remove "$WT_ROOT/$slug"
    git branch -d "$slug" 2>/dev/null || true
    echo "removed $WT_ROOT/$slug";;
  prune)
    force="${1:-}"
    git worktree list --porcelain | awk '/^worktree /{w=$2} /^branch /{print w "\t" $2}' |
    while IFS=$'\t' read -r path ref; do
      case "$path" in "$WT_ROOT"/*) ;; *) continue;; esac
      b=${ref#refs/heads/}
      merged=$(gh pr list --head "$b" --state merged --json number --jq 'length' 2>/dev/null || echo 0)
      case "$merged" in ''|*[!0-9]*) continue;; esac
      [ "$merged" -gt 0 ] || continue
      if [ "$force" = "--force" ]; then
        git worktree remove --force "$path"
        git branch -D "$b" 2>/dev/null || true
        echo "removed $path ($b — PR merged)"
      else
        echo "merged: $path ($b) — rerun 'wt.sh prune --force' to remove"
      fi
    done;;
  list)
    git worktree list;;
  *)
    echo "usage: wt.sh create <slug> [<base>] | rm <slug> | prune [--force] | list" >&2
    exit 2;;
esac
