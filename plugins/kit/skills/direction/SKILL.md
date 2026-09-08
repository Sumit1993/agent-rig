---
name: direction
description: "Answer where a repo stands and what to work on next by reading GitHub itself: the current version milestone, its open issues, p0 first, blocked skipped. Load when a session is asked what to do next, picks up work cold, or must rank a repo's queue. Reads only the repo it is in unless asked for the estate. Also the frozen label and milestone vocabulary, and what to report when a repo drifts from it."
---

# Direction

GitHub is the record and this skill is the reader. There is no script. Run the commands below with `gh` from inside the repo. Never run an unfiltered `gh issue list`; picking by recency is the failure this replaces. The ruling with the evidence is `Sumit1993/claude-kit#100`, the comment of 2026-09-08.

## The vocabulary

Nine labels, the same in every repo, and nothing else:

| kind | state | priority |
| --- | --- | --- |
| `bug`, `enhancement`, `documentation`, `decision` | `blocked`, `parked`, `needs-operator` | `p0`, `p1` |

Bot labels (`dependencies`, `github_actions`, `javascript`, `autorelease:*`) and the review-lane admission label `coderabbit_review` are mechanism, not vocabulary. Leave them alone and do not count them as drift.

A milestone is titled with the version it ships, `0.5.0`. A repo has at most two open: current and next. Line one of the description is the done-when sentence. There is no number prefix, no due date, and no order across repos.

Never create, rename or delete a label or a milestone. If the vocabulary lacks something, file an issue labelled `needs-operator` saying what and why.

## Step 1: read the repo and report drift

```
gh repo view --json nameWithOwner -q .nameWithOwner
gh label list --json name -q '.[].name'
gh api 'repos/{owner}/{repo}/milestones?state=open' --jq '.[] | "\(.title)\t\(.open_issues) open, \(.closed_issues) closed\t\(.description | split("\n")[0])"'
```

Drift is any label outside the nine and the mechanism set, more than two open milestones, or a milestone title that is not a bare version. Report drift to the operator in one line each. Do not fix it.

## Step 2: the current milestone

Current is the lowest open version. Sort the titles with `sort -V` and take the first. If the repo has no open milestone, nothing is startable; say so and stop.

## Step 3: the pick

```
gh issue list --state open --milestone '<current>' --json number,title,labels,createdAt --jq '
  map(select(.labels | map(.name) | index("blocked") | not))
  | sort_by([(.labels | map(.name) | index("p0") == null), .createdAt])
  | .[] | "#\(.number)\t\(.labels | map(.name) | join(","))\t\(.title)"'
```

The pick is the first line. `p0` sorts to the front of its own milestone and nowhere else. `blocked` is skipped; the comment on that issue names the blocker. An issue whose body says it is blocked but carries no label is a triage note: open it, and if the blocker is real, add the `blocked` label with a comment.

An issue with no milestone is not startable. Count them and report the number:

```
gh issue list --state open --search 'no:milestone' --json number --jq length
```

## Step 4: what is in flight

```
gh pr list --state open --json number,title,isDraft,updatedAt --jq '.[] | select(.title | startswith("chore(deps)") | not) | "#\(.number)\t\(if .isDraft then "draft" else "ready" end)\t\(.title)"'
```

A ready PR on the pick means the pick is already taken; move to the next line.

## The estate, only when asked

Asked where everything stands, run Step 1's milestone command once per repo with the path spelled out, `repos/owner/repo/milestones?state=open`, for `Sumit1993/claude-kit`, `Sumit1993/mage-memory`, `prismalens/prismalens`, `prismalens/gh-workflows` and `prismalens/sreforge`. Say one line per repo, the current milestone and its counts, and stop. Which repo the operator works in is the operator's choice; this skill does not rank repos.

## Handoffs

Each repo's pinned issue is the handoff log. Its last comment says where the previous session stopped. Read it after the pick, never instead of it, and never treat a list in its body as a queue.
