#!/bin/bash
# cr-evidence.sh — publish durable evidence that a CodeRabbit CLI review ran.
#
# WHY
# ---
# A CLI review happens locally and leaves nothing on the PR. Under the CLI-first
# lane most PRs never get an online review at all, so without this the merge gate
# cannot tell "reviewed by the CLI and clean" from "nobody looked at it" — the
# exact ambiguity the `review-evidence` gate exists to remove.
#
# This posts a marker comment the gate keys on:
#     <!-- cr-cli-review: <full head sha> -->
#
# The SHA matters: evidence vouches for one commit, not for the PR. Push again
# and the marker no longer matches head, so the gate goes red until the branch is
# re-previewed. That is intended.
#
# Evidence is only ever posted when a completion record for that exact SHA exists in
# the CLI preview logs (`{"type":"complete"}`). The CLI exit code cannot serve as
# that signal because a non-zero exit does not distinguish a review that found
# problems from one that never ran to completion.
#
# Safe to call when no PR exists yet (cr-preview runs pre-push): it records
# nothing and exits 0. Call it again after `gh pr create`.
#
# Usage:  cr-evidence.sh [--sha <sha>] [--quiet]
# Tracked in prismalens/prismalens#301.
set -u

QUIET=0
SHA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sha)   SHA="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "cr-evidence: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
say () { [ "$QUIET" = "1" ] || echo "cr-evidence: $*"; }
# Refusals ignore --quiet: a refusal must never be silenced because silence
# reads as success, leaving the operator with a red gate for no stated reason.
refuse () { echo "cr-evidence: $*" >&2; }

has_completion_record () {
  local repo="$1"
  local branch="$2"
  local sha="$3"

  if ! command -v jq >/dev/null 2>&1; then
    return 2
  fi

  local log_dir="$HOME/ai-context/state/kit/cr-preview/logs"
  local slug
  slug=$(echo "$repo-$branch" | tr '/' '-')

  local old_nullglob
  old_nullglob=$(shopt -p nullglob)
  shopt -s nullglob
  local logfiles=("$log_dir/$slug."*.jsonl)
  eval "$old_nullglob"

  local f fname fname_no_prefix short_sha
  for f in "${logfiles[@]}"; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    fname_no_prefix="${fname#"$slug."}"
    short_sha="${fname_no_prefix%.jsonl}"

    if [ -n "$short_sha" ] && [[ "$sha" == "$short_sha"* ]]; then
      if jq -e 'select(.type == "complete")' "$f" >/dev/null 2>&1; then
        return 0
      fi
    fi
  done

  return 1
}

KIT_META="$(dirname "$0")/kit-meta.sh"
repo=$("$KIT_META" current 2>/dev/null | jq -r '.repo // empty')
[ -n "$repo" ] || { say "not in a github repo — nothing to do"; exit 0; }

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0

# The SHA a CLI review vouches for. Prefer an explicit --sha, then the one
# cr-preview.sh recorded.
MARK_DIR="$HOME/ai-context/state/kit/cr-preview"
shafile="$MARK_DIR/$(echo "$repo-$branch" | tr '/' '-').sha"
[ -n "$SHA" ] || SHA=$(cat "$shafile" 2>/dev/null)
case "$SHA" in ''|*[!0-9a-f]*) say "no usable sha — nothing to do"; exit 0 ;; esac

# A PR may not exist yet; cr-preview runs pre-push. Not an error.
# `--head` selects by branch and is a `gh pr list` flag — `gh pr view` does not
# take it and silently resolves something else, so list is the correct call here.
# `.[0]` on an empty array yields "null null", not empty — guard on length.
pr=$(gh pr list --repo "$repo" --head "$branch" --state open --limit 1 \
     --json number,headRefOid \
     -q 'if length > 0 then "\(.[0].number) \(.[0].headRefOid)" else empty end' 2>/dev/null) || pr=""
[ -n "$pr" ] || { say "no open PR for $branch yet — re-run after 'gh pr create'"; exit 0; }
num=${pr%% *}
head=${pr##* }

if [ "$head" != "$SHA" ]; then
  say "reviewed $SHA but PR #$num head is $head — not posting stale evidence"
  exit 0
fi

has_completion_record "$repo" "$branch" "$SHA"
rc=$?
if [ "$rc" -eq 2 ]; then
  refuse "jq is required to verify review completion — evidence will not be posted"
  exit 1
elif [ "$rc" -ne 0 ]; then
  refuse "no completed CLI review found for $SHA — evidence will not be posted"
  exit 1
fi

marker="<!-- cr-cli-review: $SHA -->"

# Idempotent: one marker per SHA, however many times this is called.
if gh api "repos/$repo/issues/$num/comments?per_page=100" \
     --jq '.[].body' 2>/dev/null | grep -qF "$marker"; then
  say "evidence for ${SHA:0:8} already posted on #$num"
  exit 0
fi

body="$marker
🐇 **CodeRabbit CLI review** ran locally against this diff at \`${SHA:0:8}\`.

This is the durable record the \`review-evidence\` status keys on. It attests that
an independent reviewer examined this commit — not that every finding was accepted.
Push again and this evidence no longer applies to the new head, by design.

<sub>Posted by \`cr-evidence.sh\`. See prismalens/prismalens#301.</sub>"

if gh pr comment "$num" --repo "$repo" --body "$body" >/dev/null 2>&1; then
  say "posted evidence for ${SHA:0:8} on #$num"
else
  say "WARNING: failed to post evidence on #$num" >&2
  exit 1
fi
