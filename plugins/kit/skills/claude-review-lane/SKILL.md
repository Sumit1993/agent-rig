---
name: claude-review-lane
description: "How our Claude review lane (`claude[bot]`) behaves on any PR of any age: reading the liveness comment's four verdicts, the ways the lane stays quiet (skipped author, auto-pause, fork head, self-skip), the summon grammar (`@claude review`, `@claude full review`, the per-run `--model` override), verification rounds, and who may resolve a `claude[bot]` thread. Load when a `claude[bot]` thread or a liveness comment is in front of you, when the lane has gone quiet or a review is missing, when deciding whether to summon or re-summon, and when judging whether a head has actually been reviewed before it merges. Arming a watcher on a PR this session raised is `pr-watch` instead."
metadata:
  version: "1.0.0"
---

# The Claude review lane

The lane is `claude-code-review.yml` in `prismalens/gh-workflows`, called by a thin stub in each
consumer repo. This skill is how an operator works with it: reading what it said, knowing when it
said nothing, and summoning it when nothing is what you got. It applies to any open PR, whatever
session raised it.

Two boundaries. `AGENTS.md` decides **which** reviewer a PR gets; this skill never repeats that
choice. `pr-watch` covers watching a PR this session raised, the CodeRabbit lane, and the merge
mechanics, and it owns the maintenance rule for the canonical narrative both skills point at,
`claude-kit/docs/pr-review-process.html`.

Callee truth is the workflow file, never a local checkout:

```bash
gh api repos/prismalens/gh-workflows/contents/.github/workflows/claude-code-review.yml --jq .content | base64 -d
gh api repos/prismalens/gh-workflows/contents/README.md --jq .content | base64 -d
```

## 1. The two standing rules

- **Silence is never approval.** No posted findings means this head has no machine review on
  record. It does not mean the diff is clean. Treat an unreviewed head exactly as you would treat
  a rate-limited one.
- **A green job is not evidence.** The lane publishes no commit status and gates nothing. A run
  can finish `success` having posted zero comments, and a run that self-skips reports nothing at
  all. Read for **posted output**; never read a check's colour as a review.

Both rules exist because the only thing that certifies a review happened is the liveness comment,
and the only thing it certifies is what was posted.

## 2. Reading the liveness comment

Every run that reaches the reviewer upserts one comment authored by `github-actions[bot]`, opening
with a marker:

```
<!-- claude-review-liveness rounds=N sha=<40-hex> -->
**Claude review lane** — [run](...): <verdict>
```

**Match the prefix `<!-- claude-review-liveness`, never the whole marker.** Both fields change
from round to round: `rounds=` counts automatic rounds that actually reviewed, and `sha=` records
the last head on which the lane **published** output. `sha=` advances on posted evidence only,
never on a job result, so a green run that posted nothing does not move the baseline past commits
no reviewer read. The field is omitted entirely when there is no baseline, so its absence is
unambiguous: either nothing has ever posted on this PR, or the marker predates the field. Nothing
consumes `sha=` yet; it is groundwork for an incremental review range.

Four verdicts, and only the first one means the head was reviewed:

| Verdict text | What it means | What to do |
|---|---|---|
| `reviewed <sha> and posted N inline / M summary comment(s)` | The lane read this head and published. This is the only verdict that counts as review evidence | Work the threads |
| `finished on <sha> (job result: ...) but posted **nothing**` | The run completed and published nothing. This head has no machine review | Read the run log for tool denials, then `@claude full review`. If that also comes back empty, escalate to `coderabbit_review` or a model pass |
| `auto-paused after N automatic rounds at <sha>` | The lane hit `auto_pause_rounds` and declined to review. Not reviewer output | Summon with `@claude review`, or hand the pause back to whoever owns the PR. Never wait for the next push |
| `did not run at <sha>: no CLAUDE_CODE_OAUTH_TOKEN reached this lane` | The caller stub failed to map the secret across the owner boundary | Fix the stub. `secrets: inherit` does not cross owners, so the mapping must be explicit |

**No liveness comment at all is its own signal**, and the trap that costs the most time: the
comment is only upserted when the review job actually ran, so a PR the lane never admitted has
nothing to read, and a watcher waiting for one waits forever. Section 3 lists every case.

## 3. Admission, and every way the lane stays quiet

Automatic rounds fire on `pull_request` for same-repo heads. A summon also requires an
org-member author (`OWNER`, `MEMBER`, or `COLLABORATOR`), an explicit verb, and an open PR.

Five ways a PR gets no review. The first four produce no liveness comment either:

1. **Skipped author.** A PR whose author is in `skip_authors` (default `dependabot[bot]`) gets no
   automatic round: no review, no verify, no liveness comment. Matching is exact-login on a
   delimiter-wrapped list, so `bot` never collides with `dependabot[bot]`. A summon bypasses the
   list, because manual intent wins.
2. **Draft PR.** Automatic rounds skip drafts on both the caller stub and the callee. Declared
   unfinished code is not worth the spend. A summon reaches a draft anyway.
3. **Fork head.** Never machine-reviewed by this lane. GitHub withholds repository secrets from
   fork code and the lane deliberately avoids `pull_request_target`. A separate `fork-notice` job
   upserts a comment marked `<!-- claude-review-fork-notice -->` saying so and pointing at the
   `coderabbit_review` label, so the PR is not silently quiet. A summon does not override this in
   v1. When the fork run holds a read-only `GITHUB_TOKEN` (the default, unless the repository
   enables *Send write tokens to workflows from fork pull requests*) the comment is denied and the
   job falls back to a workflow warning annotation carrying the same text, which is easy to miss.
4. **Self-skip on the workflow itself.** A PR that edits `.github/workflows/claude-code-review.yml`
   is never reviewed: `claude-code-action` self-skips on workflow-validation mismatch. This is a
   security control and the one case a summon cannot fix, so label such a PR `coderabbit_review`
   instead. A self-skip leaves the action's conclusion empty, which looks identical to a tool
   denial that aborted a run midway; the difference is that a denial may have posted some findings
   first. The liveness comment says which, and the run log says why.
5. **Auto-paused.** After `auto_pause_rounds` automatic rounds (default 5) the lane pauses itself
   and posts the auto-paused verdict instead of reviewing. This one does leave a liveness comment.
   **A paused PR is not reviewed on push, so a wait keyed on the next push has no end.** The
   counter is monotonic in v1 and never resets, so a summon resumes the lane for exactly one run.

## 4. Summon grammar

Bare PR comments, org members only. The comment body is read only by workflow `contains()`
expressions and never reaches a prompt, so a summon carries no instructions: put context in the PR
body, which the review reads anyway.

| Comment | Effect |
|---|---|
| `@claude review` | Incremental. The lane decides its own mode: a verify round when unresolved `claude[bot]` threads exist, otherwise a normal review. The only resume for an auto-paused PR |
| `@claude full review` | From scratch, with dedup disabled for that run. The fix for a round that finished green having published nothing, which is what dedup silently causes (prismalens/prismalens#410) |
| `@claude review --model opus` | Incremental on `claude-opus-5` for that run only. `--model sonnet` picks `claude-sonnet-5` back |

`default_model` is `claude-sonnet-5` on purpose: review is the highest-volume Claude spend across
the consumer repos, so escalation is per-run and deliberate. Which model IDs resolve at all is set
by the repo's `CLAUDE_CODE_OAUTH_TOKEN` tier, not by the input.

**The override is an allowlist of two fixed phrases, matched whole.** Two consequences worth
knowing before you type:

- `@claude full review --model opus` does **not** switch models. `@claude review --model opus` is
  not a substring of it, so the run falls through to `default_model`. There is no phrase that
  combines a full review with a model override; pick one.
- Anything else after `--model`, including `haiku`, is ignored rather than rejected, and the run
  uses `default_model`.

**One summon per round.** Each mention is a full agent run. Batch every fix, push, then summon
once. A summon never cancels an in-flight automatic round; it queues behind it, while a push
supersedes anything queued, summons included.

## 5. Verification rounds

A push to a PR that still has unresolved `claude[bot]` threads gets a verify round instead of a
stock re-review. Three differences that change how you read it:

- **Per-thread verdicts.** Each unresolved thread gets exactly one of `verified fixed in <8-char
  sha>` or `not addressed: <reason>`, judged against the code as it now stands.
- **Delta-only review.** New findings are posted as inline comments as usual, but a finding an
  existing thread already covers is not re-posted.
- **A mandatory summary comment.** Its first line is exactly
  `## Code review — verification round`, and it carries a table of thread URL against verdict.
  It is posted even when everything is fixed and nothing is new, so its absence means the verify
  round did not complete.

## 6. Who resolves a `claude[bot]` thread

The reviewer resolves threads it can verify as fixed. A human rules on anything disputed,
declined, or deferred:

1. **Reviewer posts finding:** opened as an inline review thread.
2. **Non-bot replies in-thread:** asserting the finding is fixed in a commit or disputing the
   finding. A reply from a non-bot account is the trigger; the reviewer does not resolve threads
   on a push alone. The lane excludes GitHub App identities so its own reply cannot retrigger it,
   so an agent replying through a member's credential is admitted.
3. **Reviewer re-evaluates:** checks the finding against current PR head.
4. **Verified fixed:** the reviewer resolves the thread directly, citing the commit SHA and what
   it checked.
5. **Not verified:** the reviewer leaves the thread open and explains why.

**Disputed, declined, or deferred findings are resolved by a human and by nobody else.** If you
decline or defer a finding, post the disposition in-thread first, then resolve the thread manually
via GraphQL `resolveReviewThread` or the UI. The reviewer only resolves what it proves fixed in
code; judgment calls and scope decisions stay with the human operator.

## 7. Before a merge

The question a merge asks of this lane is narrow: **has posted review output landed on the head
that is about to merge?** Only the `reviewed <sha> and posted ...` verdict answers yes. An
auto-paused comment, a posted-nothing comment, a fork notice, and no comment at all are all the
same answer: this head is unreviewed. Summon and wait for the posted review, or make a deliberate
risk decision to merge without one. `pr-watch` owns the merge and queue mechanics that consume
this answer.

## 8. Finding labels and parse contract

Every review finding opens with a header line containing three fields:

```
_<Category>_ | _<Severity>_ | _<Effort>_
```

Example: `_🎯 Functional Correctness_ | _🟠 Major_ | _⚡ Quick win_`

### Controlled vocabulary

Ten standard labels across three dimensions:

| Dimension | Labels |
|---|---|
| Category | `Functional Correctness`, `Security & Privacy`, `Maintainability & Guidelines`, `Data Integrity & Integration`, `Stability & Availability` |
| Severity | `Critical`, `Major`, `Minor` |
| Effort | `Quick win`, `Heavy lift` |

### Parse contract

- **Field grammar:** `_[<emoji> ]<label>_`. Fields are separated by ` | `.
- **Emoji are presentation only.** Strip leading non-ASCII bytes, trim whitespace, then exact-match the remaining ASCII label against the closed vocabulary. Never compare emoji bytes. Two of the ten emoji carry a U+FE0F variant selector and one is text-default, so byte comparison breaks.
- **Unrecognized labels:** Route the finding to the fallback class `Major / Heavy lift` and log a parse notice. A finding is never dropped.
- **Missing header (legacy comments):** Default to `Category: Functional Correctness`, `Severity: Major`, `Effort: Heavy lift`.

