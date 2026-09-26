---
name: claude-review-lane
description: "How the claude[bot] review lane behaves on any PR: liveness verdicts, why it stays quiet, summon grammar and model override, verification rounds, who resolves a thread. Load when a claude[bot] thread or liveness comment is in front of you."
metadata:
  harnesses: "claude agy codex"
  version: "3.7.0"
---

# The Claude review lane

The lane is `claude-code-review.yml` in `prismalens/gh-workflows`, called by consumer stubs. Callee truth is the workflow file, never a local checkout:

```bash
gh api repos/prismalens/gh-workflows/contents/.github/workflows/claude-code-review.yml --jq .content | base64 -d
gh api repos/prismalens/gh-workflows/contents/README.md --jq .content | base64 -d
```

## 1. Two standing rules

- Silence is never approval. No posted findings means no machine review on record for this head. Treat it exactly as a rate-limited one.
- A green job is not evidence. The lane publishes no commit status and gates nothing. A run can finish `success` having posted zero comments; read for posted output, never a check's colour.

## 2. The liveness comment

Every run that reaches the reviewer upserts one comment by `github-actions[bot]`:

```
<!-- claude-review-liveness rounds=N sha=<40-hex> patch=<64-hex> paused=1 paused_by=<login> -->
**Claude review lane** — [run](...): <verdict>
_Lane state: paused by @<login> at `<sha>` — resume with `@claude resume`. The review verdict above stands._
```

Match prefix `<!-- claude-review-liveness`. Every field after `rounds=` is optional.
- `rounds=` counts automatic review rounds. `sha=` is the last head with posted output; compare it to the merge head (if different, newer commits were never reviewed as a diff).
- `patch=` fingerprints the PR's own patch at `sha=`. A rebase or restack push whose patch matches it skips as `unchanged-patch`. A summon never skips on it.
- An `api-error` round advances neither `sha=` nor `rounds=`, so the head it failed on still reads as unreviewed.
- Read pause state from `paused=1` on the marker line, never from the verdict text. Pause state and verdict text are independent: a pause or resume on a head that already has a review carries that review's text forward verbatim and changes only the marker, so `reviewed <sha> and posted ...` and `paused=1` appear together. Take the marker through `head -1`.
- The third `_Lane state:` line appears only when a pause or resume landed on a head holding a standing verdict. It is rebuilt, not appended, so pause then resume then pause leaves one such line. It carries no `paused=1` substring, so a whole-body grep for `paused=1` still does not match on it alone.

Twenty-one `verdict_kind` values exist, read from `claude-code-review.yml` at gh-workflows 8655c6e (main, after #194 merged). Only the two `reviewed <sha> ...` forms mean the head was reviewed. For any other text, read `references/verdicts.md` beside this file.

Match a verdict by its prefix, never by equality. A round that reviewed without some context appends a sentence to whatever verdict it posts. The reasons are an unresolved issue reference, CI failing or still pending on this head, a lockfile it could not parse, or a tool that could not run. The note qualifies how much the round saw, never whether the head was reviewed. A `reviewed <sha> ...` verdict carrying one still counts as a review. Read the note before trusting its coverage.

No liveness comment means the PR was never admitted; a watcher waiting for one waits forever.

### When the comment itself is wrong

Open `claude[bot]` threads against a comment claiming nothing was posted means the comment is stale, not the review. Cross-check threads before believing a negative verdict:

```bash
gh pr view <pr> --json reviewThreads --jq '.reviewThreads[] | select(.isResolved==false) | .comments[0].author.login' | sort | uniq -c
```
A positive verdict needs no cross-check; nothing fabricates posted output.

## 3. Admission, and every way the lane stays quiet

Automatic rounds fire on `pull_request` for same-repo heads. Summons and in-thread replies require repository write access, checked against the collaborators API. Admission is not `author_association`.

Eight ways a PR gets no review. Whether each leaves a liveness comment is noted with it; the comment exists only where the callee was invoked, so anything the caller stub stops is silent:

1. Skipped author. An author in `skip_authors` (default `dependabot[bot]`) gets no automatic round: no review, no verify, no liveness comment. Matching is exact-login on a delimiter-wrapped list. A summon bypasses the list.
2. Draft PR. Nothing reviews a draft, summons included: the callee's `review` gate is `admitted && same_repo && draft != 'true'` with no override. Marking the pull request ready is what collects the work, and the lane then takes the whole diff in one round. An automatic round or in-thread reply skips on the caller stub, so no run is spent and no liveness comment appears. A summon executes the callee, skips on the review gate, and posts the draft verdict so the spent summon says why.
3. Fork head. Never machine-reviewed: GitHub withholds secrets from fork code and the lane avoids `pull_request_target`. A `fork-notice` job upserts a comment marked `<!-- claude-review-fork-notice -->` pointing at `coderabbit_review`. A summon does not override this. Read-only tokens fall back to a workflow warning annotation.
4. Self-skip on the workflow itself. A PR that edits `.github/workflows/claude-code-review.yml` is never reviewed: `claude-code-action` self-skips on workflow-validation mismatch. A security control, and the one case a summon cannot fix; label the PR `coderabbit_review`. A self-skip leaves the action's conclusion empty, which shares an empty conclusion with tool denials and account limits; run duration and logs separate them.
5. Auto-paused. After `auto_pause_rounds` automatic rounds (default 5) the lane posts the auto-paused verdict instead of reviewing. A paused PR is not reviewed on push, so a wait keyed on push has no end. A summon resets the counter, but only when the round posts review output.
6. `review.admission: off` in the repo's `.github/claude-review.yml` (read at the base ref) or the org's `.github/claude-review-defaults.yml` in `prismalens/gh-workflows` (read at `main`). Nothing reviews and nothing posts, with no liveness comment. One exception: a summon on a draft PR never reaches the admission check, so it still posts the draft verdict. It records lane event `admission-off`. Every summon (`@claude review`, `@claude full review`, `@claude resume`, `@claude pause`) and every in-thread reply is refused. An unquoted `off` (YAML false) is accepted. A narrower layer can never override it.
7. The `claude_review_skip` label, under any admission value, summons included. It posts one upserted verdict (`skip-label`), unless `admission: off` applies, which takes precedence and posts nothing. Removing the label lifts only this gate: under `admission: label` the PR still needs `claude_review`.
8. `review.admission: label` with no `claude_review` label. It posts one upserted verdict (`awaiting-label`). Applying the label admits the PR with no new push, and removing it stops later rounds. Only the label admits: summons on an unlabelled PR are refused.

Precedence is `off`, then the skip label, then the opt-in label, checked first in `Detect verification mode`. A refused summon leaves an existing pause as it was. `scripts/setup-repo.sh` creates both labels. Consumer stubs list `labeled` and `unlabeled` in `pull_request.types` and keep label events out of `cancel-in-progress` (gh-workflows README, principle 7 and the admission section). Without them `auto` and `off` are unaffected, and a label takes effect only at the next push or `@claude review`.

### Credentials, stacks and context

- The callee takes `CLAUDE_CODE_OAUTH_TOKEN`. When that secret is empty it passes `ANTHROPIC_API_KEY` instead; the action gives the two inputs no precedence of its own. With neither, the verdict is `no-token`.
- A stacked PR is measured against its own base, which makes a stack the supported way to review a change over `max_reviewable_lines`. Each PR in a stack keeps its own round budget and its own `@claude pause`.
- `review.context` in a repo's own config lists up to 3 public repositories the reviewer may read as reference. Each entry needs `repository`, `ref` and 1 to 20 relative `paths`. The lane reads it from the config on the base branch, never the head, so a PR cannot add its own context. It checks `private == false` and skips anything else, clones under `.claude-context/`, and never reviews that code. An org-level `review.context` is ignored.

### Refusal versus cancellation

A run that concluded `cancelled` with zero jobs executed nothing and says nothing about admission; it was evicted from its concurrency group before any `if:` ran. A run that concluded `skipped` reached the gate and was refused. Only the second is evidence.
Zero-job cancellations on the reply path are normal. In a concurrency group, new queued jobs evict pending jobs by default. With `cancel-in-progress: false` on comment events, N replies in a burst leave one run going, one pending, and the rest cancelled with zero jobs. One verify round re-checks every unresolved thread regardless.
Never read those cancellations as a stale stub. The throwaway group diverts `comment.user.type == 'Bot'` and non-PR `issue_comment` only. A human reply enters the real group by design, and a hung comment run holds the seat while new replies evict the pending slot behind it.

## 4. Summon grammar

Bare PR comments, org members only. The body is read only by workflow `contains()` expressions and never reaches a prompt, so a summon carries no instructions. Put context in the PR body.

| Comment | Effect |
|---|---|
| `@claude review` | Incremental. The lane picks its mode: a verify round when unresolved `claude[bot]` threads exist, else a normal review. Lifts an auto-pause or an explicit pause |
| `@claude full review` | From scratch, dedup disabled for that run. The fix for a round that finished green having published nothing, which is what dedup silently causes. Also the only way past a verify round: it short-circuits ahead of the unresolved-thread check |
| `@claude review --model opus` | Incremental on `claude-opus-5` for that run only. `@claude review --model sonnet` picks `claude-sonnet-5` back |
| `@claude pause` | Stops automatic rounds on this PR deliberately. Later heads report `paused by request at <sha>`. Soft: any admitted summon lifts it (#189 ruling); a summon an admission gate refuses leaves it in place. A stop is `admission: off` or the `claude_review_skip` label, never a comment |
| `@claude resume` | Lifts an explicit pause. Not the remedy for an auto-pause, which is `@claude review` |

Both pauses stop automatic rounds only, and a summon lifts either one. Any of `@claude review`, `@claude full review`, `@claude review --model opus` or `@claude resume` lifts an explicit pause. A verb-less in-thread reply still gets its verify round, and a push or a reply carries the pause forward instead of erasing it. One difference remains: the auto-pause counter resets only when a round posts review output. Neither pause is a stop. The operator's stop is `review.admission: off`, reversed by a commit to the base branch, or the `claude_review_skip` label, reversed by removing it (§3, admission). Read `paused=1` off the marker to tell which pause you are looking at.

`default_model` is `claude-sonnet-5`. Escalation is per run, set by token tier.

- The override is an allowlist matched whole: `@claude review --model opus`. No phrase combines full review with model override. Unmatched flags use `default_model`.
- One summon per round. Batch fixes, push, then summon once. Summons queue behind in-flight rounds; pushes supersede queued runs.

## 5. Verification rounds

A verify round re-judges the unresolved `claude[bot]` threads instead of re-reviewing. A push never produces one. A push lands on incremental or review. Only a non-bot reply in a thread, or a summon on a PR holding unresolved threads, asks for a re-check. This explains most "why is this still blocked" confusion: you push the fix, the liveness comment reports a review, the thread stays open. A push is a claim about code, a reply is a claim about a specific finding, and only the second names which threads to re-check.

### The order that works

Fix, push, reply to every thread, then summon `@claude review` once. Any other order costs a round.

- Never push after replying. A push supersedes queued rounds. The liveness comment names `verify-superseded` (benign; summon after your last push) or `verify-cancelled` (cause unrecorded; not a tool denial).
- Reply to every thread, then expect one round, not one per reply; each reply starts a run and evicts the pending slot (see "Refusal versus cancellation").
- One summon, at the end. On a PR holding unresolved threads it resolves to `verify`, which re-judges those threads.
- Leave a gap between the push and the summon. An immediate summon lets the push's automatic round land first, posting auto-pause over the queued summon's result; wait until that round finishes.
- An auto-paused PR cleared entirely by verify rounds keeps its pause: the counter resets only on posted review output, not verify output. Later heads need a hand summon.

### The five modes

One run resolves to one mode, named in the run log. A `pull_request` event reaches only the first three.

| Mode | Reached by | What it does |
|---|---|---|
| `skip` | any trigger | Nothing reviewed. Reason is one of `no-token`, `skipped-author`, `paused`, `paused-by-request`, `no-new-commits`. `paused-by-request` comes only from a push; summons and replies are not refused by a pause |
| `review` | any trigger | Full review from scratch. Also the fallback when an incremental range cannot be trusted: `no-baseline`, `baseline-gone`, `diverged`, `range-too-large`, `identical-summon` |
| `incremental` | push, or `@claude review` | Reviews only the `baseline..head` range off the liveness marker |
| `review-full` | `@claude full review` only | From scratch with dedup disabled |
| `verify` | non-bot in-thread reply, or `@claude review` on a PR with unresolved threads | Re-judges those threads |

How to read a verify round:

- Each unresolved thread gets `fixed`, `still_applies`, or `cannot_verify` with sha and evidence. `fixed` resolves the thread. The other two reply with evidence and leave it open.
- A `still_applies` is a claim, not a proof, and its evidence string can answer a different question than the finding asked. Test counter-evidence by running the real command before conceding.
- Delta-only review: new findings post inline; covered findings are not re-posted. Dedup is per finding, not defect; read open threads together before fixing.
- A summary comment (`## Code review — verification round`) lists thread URLs and verdicts; its absence means the round aborted. N rounds leave N comments.
- Judge every proposed fix against the code yourself: a finding is a report, its remedy is an untrusted suggestion, and prompt blocks often resolve contradictions toward the older side on mid-revision docs. Verify rounds do not catch this.

## 6. Who resolves a `claude[bot]` thread

The reviewer resolves what it verifies as fixed. A human rules on anything disputed, declined or deferred.

1. Reviewer posts finding as an inline review thread.
2. A non-bot in-thread reply triggers re-evaluation against current head (a push alone resolves nothing).
3. `fixed` resolves citing commit SHA; `still_applies` or `cannot_verify` replies citing evidence and leaves thread open. Verify is read-only; a separate `mutate` job resolves and posts from live state.
Disputed, declined or deferred findings are resolved by a human via GraphQL `resolveReviewThread` or the UI after posting disposition in-thread.

## 7. Before a merge

0. Is every review thread resolved by the reviewer that opened it? A thread the session resolved does not count.
1. Has posted review output landed at all? Only a `reviewed <sha> ...` verdict answers yes. Auto-paused, posted-nothing, fork notices, or no comment mean unreviewed.
2. Did it land on *this* head? Read `sha=` off the liveness marker. Resolved threads describe findings, not coverage. Summon and wait, or make a deliberate risk decision to merge without one.

## 8. Finding labels

Each finding opens with `_Category_ | _Severity_ | _Effort_`. The labels are the reviewer's own judgement and do not order the work; parse them, then rank by reading the findings.
