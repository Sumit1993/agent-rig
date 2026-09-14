---
name: triage
description: "Before any gh issue create, comment, edit or close: search what already exists, fold or file, shape the body, link and close it right."
metadata:
  harnesses: "claude agy codex"
  version: "1.0.0"
---

# Triage

Every issue write starts with a read. Filing without searching is how one story ends up in three issues.

## 1. Search, open and closed

```
gh search issues "<two or three keywords>" --owner "$(gh repo view --json owner -q .owner.login)" --include-prs --limit 15 \
  --json repository,number,state,title --jq '.[] | "\(.repository.nameWithOwner)#\(.number)\t\(.state)\t\(.title)"'
```

Add one `--owner` per account or org you work in. Run it again with synonyms. Read titles, then open only the hits that match with `gh issue view <n> --comments`. A duplicate of a closed ruling is worse than a duplicate of an open issue.

## 2. Fold or file

| The best hit is | Do |
| --- | --- |
| Open, same unit of work (same files, same verification) | Comment on it. Do not file. |
| Closed, and its ruling still covers this | Act on the ruling. Comment only with a new fact. |
| Closed, and wrong now | File new, and Pointers names it with the evidence that changed. |
| Related, a different unit | File, and Pointers names it. |
| Nothing | File. |

Findings on one surface are one umbrella issue, not one issue each. When an issue and a ruling disagree, the ruling wins and the issue is rewritten to match. A ruling carries the operator's sign-off; a comment marked "sign-off pending" is a proposal, so ask.

## 3. Shape

Title is the outcome. The body has three sections, plus the agent marker line `gh-body-stamp.sh` requires:

```
## Goal
At most two lines.
## Done when
- [ ] A check a stranger can run: a file, a command, an observable result.
## Pointers
Files, `#N - title`, PRs. No summaries.
```

- No history and no evidence essay in the body. Evidence and exact commands go in a comment, copied in, because a scratch path is a broken link.
- Cite every issue or PR with its title.
- A parked issue keeps its outcome in Goal and adds one line there: `Parked because <reason>`.
- Labels and milestone come from the `compass` vocabulary where the repo has it installed. A repo without it is not drift; leave both off.
- An umbrella's Done when carries one checkbox per folded member, with the member's `#N - title`, so a closed member stays findable. The member's surviving checks go under it, each prefixed `#N:`.

## 4. Rewrite, fold, close

- Before rewriting or closing, check every present-tense claim ("main is red", "not built") against the remote default branch, via `gh api` or after `git fetch`, never a working tree. Cite the command. A rewrite that restates a stale claim launders it.
- The command must be able to fail if the claim is false. Another issue's open or closed state proves nothing about a sentence in this one.
- Before editing a body, move its evidence and exact commands verbatim into one comment, unless a comment already holds them. Edit history is not a record. Where the evidence links a scratch file, copy the file's content in, not the link.
- A ruling that changes the work edits the body's Done when. The comment holds the why.
- Rewriting many issues goes through drafts in files, a review, then one apply script. Never live edits one by one; a half-reshaped queue is worse than none. The script records each step it lands and skips it on a rerun, so a retry posts no duplicate comments.
- A state claim uses live state with its number: `open`, `drafted`, `in review`, `merged`, `shipped`. Done means merged.
- A PR links issues with the keyword repeated, `closes #a, closes #b`, then `gh pr view <n> --json closingIssuesReferences` confirms.
- Close done work with `--reason completed` and a pointer to the PR or commit that did it.
- A fold closes the member with `--reason "not planned"` and `Folded into #m - title`, only after the umbrella's edit has landed; confirm it with `gh issue view <m>` first.
