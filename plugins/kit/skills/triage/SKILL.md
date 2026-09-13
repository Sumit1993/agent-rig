---
name: triage
description: "Before any gh issue create, comment, edit or close: search what already exists, fold or file, shape the body, link and close it right."
---

# Triage

Every issue write starts with a read. Filing without searching is how one story ends up in three issues. The shape rules were ruled on `Sumit1993/claude-kit#123`, the search gap is `#120`.

## 1. Search, open and closed

```
gh search issues "<two or three keywords>" --owner Sumit1993 --owner prismalens --include-prs --limit 15 \
  --json repository,number,state,title --jq '.[] | "\(.repository.nameWithOwner)#\(.number)\t\(.state)\t\(.title)"'
```

Run it again with synonyms. Read titles, then open only the hits that match with `gh issue view <n> --comments`. A duplicate of a closed ruling is worse than a duplicate of an open issue.

## 2. Fold or file

| The best hit is | Do |
| --- | --- |
| Open, same unit of work (same files, same verification) | Comment on it. Do not file. |
| Closed, and its ruling still covers this | Act on the ruling. Comment only with a new fact. |
| Closed, and wrong now | File new, and Pointers names it with the evidence that changed. |
| Related, a different unit | File, and Pointers names it. |
| Nothing | File. |

Findings on one surface are one umbrella issue, not one issue each. When an issue and a ruling disagree, the ruling wins and the issue is rewritten to match.

## 3. Shape

Title is the outcome. The body has three sections and nothing else:

```
## Goal
At most two lines.
## Done when
- [ ] A check a stranger can run: a file, a command, an observable result.
## Pointers
Files, `#N - title`, PRs. No summaries.
```

No history and no evidence essay in the body. Evidence goes in a comment, copied in, because a scratch path is a broken link. Cite every issue or PR with its title. Labels and milestone come from the `compass` vocabulary; an issue with no milestone is not startable, so set one or say why not.

## 4. Keep it current

- A ruling that changes the work edits the body's Done when. The comment holds the why.
- A state claim uses live state with its number: `open`, `drafted`, `in review`, `merged`, `shipped`. Done means merged.
- A PR links issues with the keyword repeated, `closes #a, closes #b`, then `gh pr view <n> --json closingIssuesReferences` confirms.
- Close with a pointer to the PR or commit that did the work. A fold closes with `Folded into #m` once #m's Done when carries the item.
