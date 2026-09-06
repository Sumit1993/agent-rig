#!/usr/bin/env bash
# Where are we, what next. A goal is a milestone whose title starts with a three-digit order
# ("010 R1 — ..."); the order is estate-wide. The pick is section 4's first line: p0 issues
# first inside the current goal, then creation order. p0 outside the current goal is a flag,
# not a pick. Ruling: Sumit1993/claude-kit#100.
set -uo pipefail
REPOS="Sumit1993/claude-kit Sumit1993/mage-memory prismalens/prismalens prismalens/gh-workflows prismalens/sreforge"
OWNERS="--owner Sumit1993 --owner prismalens"
EXCL='["blocked","needs-operator","parked"]'
GOAL='test("^[0-9]{3} ")'
FOCUS="${1:-}"   # optional owner/name; section 4 descends only there

ms_json() { gh api "repos/$1/milestones?state=open&per_page=100"; }
declare -A CUR
for r in $REPOS; do
  CUR[$r]=$(ms_json "$r" | jq -r '[.[] | select(.title | '"$GOAL"')] | sort_by(.title[0:3]) | .[0].title // empty')
done

echo "# Direction, $(date -I)"
echo
echo "## 1. p0 (front of the current goal, cap 5). Anything not OK here is a triage flag, not a pick."
gh api graphql -f q='user:Sumit1993 user:prismalens is:issue is:open label:p0' \
  -f query='query($q:String!){ search(query:$q, type:ISSUE, first:20){ nodes{ ... on Issue { number title createdAt repository{nameWithOwner} milestone{title} labels(first:20){nodes{name}} } } } }' \
  | jq -r --argjson x "$EXCL" --argjson cur "$(for r in $REPOS; do printf '%s\t%s\n' "$r" "${CUR[$r]}"; done | jq -Rs 'split("\n") | map(select(length>0) | split("\t") | {key:.[0], value:.[1]}) | from_entries')" '
    .data.search.nodes | sort_by(.createdAt)[] | (.repository.nameWithOwner) as $r
    | (if (.milestone.title // "") == "" then "NO MILESTONE"
       elif any(.labels.nodes[].name; IN($x[])) then "BLOCKED"
       elif .milestone.title != $cur[$r] then "LATER GOAL: \(.milestone.title)"
       else "OK" end) as $s
    | "\($r)#\(.number)\t\($s)\t\(.title)"'
echo
echo "## 2. Goals in order (milestones titled NNN ...). Lowest number per repo is current."
for r in $REPOS; do
  ms_json "$r" | jq -r --arg r "$r" '
    .[] | select(.title | '"$GOAL"')
    | [ .title[0:3], $r, .title[4:], "\(.closed_issues)/\(.open_issues + .closed_issues)",
        ((.description // "") | split("\n")[0] | .[0:110]) ] | @tsv'
done | sort
echo
echo "## 3. Buckets (milestones with no order; never current)"
for r in $REPOS; do
  ms_json "$r" | jq -r --arg r "$r" '
    .[] | select(.title | '"$GOAL"' | not) | [$r, .title, "\(.closed_issues)/\(.open_issues + .closed_issues)"] | @tsv'
done
echo
echo "## 4. Descent: the pick is the first line. p0 first, then oldest, inside the current goal."
for r in $REPOS; do
  [ -n "$FOCUS" ] && [ "$FOCUS" != "$r" ] && continue
  ms="${CUR[$r]}"
  if [ -z "$ms" ]; then echo "$r: NO ORDERED GOAL, nothing is startable here"; continue; fi
  echo "$r / $ms"
  gh issue list -R "$r" --milestone "$ms" --state open --limit 200 --json number,title,createdAt,labels \
    | jq -r --argjson x "$EXCL" '
      [ .[] | select(any(.labels[].name; IN($x[])) | not) ]
      | sort_by((if any(.labels[].name; . == "p0") then 0 else 1 end), .createdAt)
      | .[0:5][] | "  #\(.number)\t\(.createdAt[0:10])\t\(if any(.labels[].name; . == "p0") then "p0" else "" end)\t\(.title)"'
done
echo
echo "## 5. Untriaged (no milestone): triage debt, not startable"
for r in $REPOS; do
  n=$(gh issue list -R "$r" --state open --search "no:milestone" --limit 500 --json number --jq length)
  printf '%s\t%s\n' "$r" "$n"
done
echo
echo "## 6. In flight: open PRs (dependabot excluded)"
for r in $REPOS; do
  gh pr list -R "$r" --state open --json number,title,isDraft,updatedAt,author \
    | jq -r --arg r "$r" '.[] | select(.author.login != "app/dependabot")
      | "\($r)#\(.number)\t\(if .isDraft then "draft" else "ready" end)\t\(.updatedAt[0:10])\t\(.title)"'
done
echo
echo "## 7. Waiting on the operator"
gh search issues $OWNERS --state open --label needs-operator --json repository,number,title \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number)\t\(.title)"'
echo
echo "## 8. Latest handoff on each repo's pinned issue"
for r in $REPOS; do
  gh api graphql -f query="query{ repository(owner:\"${r%/*}\", name:\"${r#*/}\"){ pinnedIssues(first:1){ nodes{ issue{ number title comments(last:1){ nodes{ createdAt body } } } } } } }" \
    | jq -r --arg r "$r" '.data.repository.pinnedIssues.nodes[0].issue // empty
      | "\($r)#\(.number) \(.title)\n  [\(.comments.nodes[0].createdAt[0:10] // "-")] \((.comments.nodes[0].body // "no comments yet") | split("\n")[0] | .[0:160])"'
done
