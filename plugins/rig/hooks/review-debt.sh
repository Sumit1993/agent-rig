#!/bin/bash
# SessionStart hook: surface unresolved review threads on author's open PRs. Sumit1993/rig#150.
# Rung: hook. Skipped: impossible (no harness feature queries repo review debt), check (debt changes dynamically).
set -u
in=$(cat)

raw_origin=$(git remote get-url origin 2>/dev/null) || exit 0
case "$raw_origin" in
  *github.com[:/]*) ;;
  *) exit 0 ;;
esac
repo=$(printf '%s' "$raw_origin" | sed -E 's#.*github\.com[:/]##; s#\.git$##')
case "$repo" in
  */*) ;;
  *) exit 0 ;;
esac

# --paginate walks every page of the search, not just the first 100 PRs.
query='query($endCursor: String) { search(query: "repo:'"$repo"' is:pr is:open author:@me", type: ISSUE, first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes { ... on PullRequest { number isDraft reviewThreads(first: 100) { totalCount nodes { isResolved } } } } } }'
res=$(timeout 8 gh api graphql --paginate -f query="$query" 2>/dev/null) || exit 0

items=$(jq -rs '
  [.[].data.search.nodes[]?
   | select(.isDraft == false)
   | {number, count: ([.reviewThreads.nodes[]? | select(.isResolved == false)] | length),
      unread: ((.reviewThreads.totalCount // 0) > ([.reviewThreads.nodes[]?] | length))}
   | select(.count > 0 or .unread)]
   | sort_by(.number)
   | map(if .unread then "#\(.number) (\(.count)+ open threads, more than 100 in total)"
         else "#\(.number) (\(.count) open thread\(if .count == 1 then "" else "s" end))" end)
   | join(", ")
' <<<"$res" 2>/dev/null) || exit 0

[ -z "$items" ] && exit 0

msg="Review debt in ${repo}: ${items}. Clear it before any new pick: compass Step 0."
jq -n --arg ctx "$msg" '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
