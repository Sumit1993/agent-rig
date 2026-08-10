---
name: pr-watch
description: "Stand watch on a raised PR: arm the CodeRabbit/CI Monitor, process feedback via in-thread replies, then shepherd auto-merge through the BEHIND cascade. Trigger AFTER any `gh pr create`, when a PostToolUse hook reports a PR was raised, or when the user asks to watch/babysit a PR."
metadata:
  version: "1.4.0"
---

# PR watch — the post-PR lifecycle

After a PR is raised, reviews arrive asynchronously (CodeRabbit ~3-5 min after each push; CI in ~5-10). Never poll with model turns and never rely on the user to relay events — arm deterministic watchers and process only deltas.

Scripts live in this skill's own directory (`<skill-dir>` below) — `${CLAUDE_PLUGIN_ROOT}/skills/pr-watch/` when loaded as `kit:pr-watch`; shared kit scripts (`cr-reply.sh`, `kit-meta.sh`) live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Resolve to absolute paths before handing them to a Monitor or background Bash; those shells may not inherit the variable. Watch scripts auto-detect the repo from the cwd's origin remote (`--repo owner/name` to override).

Per-repo facts (CodeRabbit enablement, review tier) come from the kit registry — `kit-meta.sh current`, backed by `data/repo-meta.json` folded with runtime observations — never from memory:

Current repo metadata: !`"${CLAUDE_PLUGIN_ROOT}/scripts/kit-meta.sh" current`

## Phase 0 — the merge contract (nothing runs pre-push)

On mage-memory, prismalens and sreforge the contract is the whole of this:

- **Required status checks are `CI gate` and `Validate PR title (conventional commits)`. Nothing else.** No review check, no evidence artifact, no marker job, no SHA-pinning, no carry-forward, no committed high-risk path list. Anything describing those describes machinery that no longer exists — including `cr-preview.sh` and `cr-evidence.sh`, which don't exist either.
- **`required_review_thread_resolution: true`** — one unresolved review thread blocks the merge. This is the only mechanism that enforces a finding, which is what makes Phase 2's in-thread protocol load-bearing rather than etiquette: a finding matters exactly as much as the thread it lives in.
- **Reviewers are advisory.** They post; no check waits on them. **A green job is never evidence** — a reviewing workflow can report `success` having posted nothing, and one did for two weeks. Read for posted comments; never read a check's colour as a review.

There is no local pre-push step: push freely. Escalate the independent lane by risk; never pay model tokens for review a cheaper layer already covers.

| Tier | When | What |
|---|---|---|
| Claude review (`claude[bot]`) | Every PR, automatic | The default reviewer. Posts findings as **inline comments** — advisory, so it blocks nothing directly, but every thread it opens does |
| CodeRabbit **PR** review (`coderabbitai[bot]`) | **Manual admission only** — apply the `review-ready` label by hand, or comment `@coderabbitai review` | The independent lane, and a scarce one: ~one review per 40 minutes **org-wide across all three repos**, Free plan, seat assignment disabled. Spending one is a deliberate human budget decision for a sensitive change, never a routine step |
| One Opus 5 pass | Non-trivial PRs | The layer neither bot can do: spec/ADR conformance, since design truth often lives in an external hub they can't see |
| Multi-agent extreme (`/code-review ultra`) | Rare | Engine-core, security/sandbox boundary, contract/schema changes only |

Never bypass the ruleset. **Batch every fix before requesting any review** — a CodeRabbit slot spent on a commit you are about to amend is spent for nothing.

### Quota — the `coderabbitai[bot]` PR lane is a shared, cooldown-gated counter

Per-developer, per-hour, rolling (docs.coderabbit.ai/management/plans#rate-limits):

| Plan | PR/hr | Files per review |
|---|---|---|
| **OSS** (our public repos) | **1–10** † | 50–150 † |
| Pro | 5 | 150 |
| Pro+ | 10 | 300 |

† varies with the project's community and popularity — **a young repo sits near the bottom**, so assume ~1–2 PR reviews/hour. The org is on the Free plan, where seat assignment is disabled outright, so this cannot be bought away.

**This counter is org-wide**, shared across every session and subagent, not per-branch or per-session. Measured on prismalens: contention between parallel agents drove the reported `waitTime` from 2 minutes to 31 to 50, and it collapsed back to 2 the moment the other agents stopped. A *successful* review costs a genuine ~40-minute cooldown on top. **Run at most one review at a time across the whole org** — fanning them out over parallel agents does not parallelise anything, it serialises them and slows every lane.

- **Every PR review run spends one** — the initial review, *each automatic incremental review after a push*, and manual `@coderabbitai review`. A fix-push loop on one PR drains the hourly budget by itself. Hence `auto_pause_after_reviewed_commits: 1` in `.coderabbit.yaml` on every enabled repo: one review per PR, then batch your fixes and re-request once.
- **Remaining capacity is not readable.** `@coderabbitai rate limit` answers with a documentation link, never a number — three to five sessions have each tried it. Do not suggest it and do not wait on it. The only signal is the `waitTime` in a `rate_limit` error from an attempt that already spent one.
- **Keep the trigger comment BARE — `@coderabbitai review`, nothing else.** A request carrying several bullet points and direct questions was read as a **chat** instead of the review command: CodeRabbit answered with an analysis chain and the hint *"For best results, initiate chat on the files or code changes"*, and **no review ran**. It looks identical to a slow review from the outside; fifty minutes were lost to it. Put the context in the **PR body**, which is read as part of the review anyway — so nothing is given up by keeping the trigger unambiguous.
- **A cooldown retry too soon is spent for nothing.** Measured: a retry 37 minutes after a successful review was rejected outright, with no wait time returned; a retry at 83 minutes was accepted. Budget **≥45 minutes**, and confirm acceptance rather than assuming it.
- **Three outcomes to distinguish when polling, not two.** After posting the trigger, wait ~60s and read the *last* `coderabbitai[bot]` comment: `rate limited` means it was rejected and nothing is coming; `initiate chat on the files` means it was misread as chat and nothing is coming; anything else means it was accepted and the review is in flight. Polling only for the review object cannot tell "working" from "never started".
- **CodeRabbit's limits:** diff only, no test runs, Sonnet-tier depth, nitpick noise. Tame with `profile: chill` in `.coderabbit.yaml`, and distil key repo invariants into its path instructions — that file is the only channel by which design decisions reach its reviews.
- Related skills: `code-review` (CodeRabbit CLI; a manual, non-gating local look — note it shadows the built-in Standards/Spec review skill), `autofix` (apply PR-thread feedback with per-change approval).

## Phase 1 — arm the watcher (immediately after `gh pr create`)

1. Seed the seen-state so existing comments are never replayed:
   ```bash
   mkdir -p ~/ai-context/state/cr-watch
   REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner); KEY=${REPO//\//-}
   gh api "repos/$REPO/pulls/<pr>/comments?per_page=100" --jq '.[] | select(.user.login|test("coderabbit")) | .id' > ~/ai-context/state/cr-watch/$KEY-pr<pr>.seen
   ```
2. Arm via the **Monitor tool** (persistent: true):
   ```
   command: <skill-dir>/watch-coderabbit.sh <pr> [<pr>...]
   description: CodeRabbit comments + CI reds on PR <pr>
   ```
   One monitor covers many PRs. If a monitor is already running for this repo, stop it (TaskStop) and re-arm with the combined PR list — the seen-state makes re-arming free.

Event lines: `NEW coderabbit <thread|reply-in-ID> — id N — path — payload <state-file> — excerpt`, `CI FAIL — <check>`, `CODERABBIT RATE-LIMITED — …`, `CODERABBIT RE-TRIGGERED — …`, `CODERABBIT RESUMED — …`, or `PR#N MERGED/CLOSED`. **The monitor emits pointers, not payloads:** the full comment body is already saved at the `payload` path — route that path, never fetch and paste bodies into the session that owns the Monitor.

**The first line is always the presence verdict.** Not every repo has CodeRabbit — the registry (`kit-meta.sh get <owner/repo> coderabbit`) is the source of truth. The watcher consults it first, then probes (a committed `.coderabbit.yaml`/`.yml`, else any `coderabbit*` author in the repo's recent issue/review comment history), records a positive probe back into the registry, and emits one of:

- `CODERABBIT ACTIVE on <repo> — watching reviews, rate limits, CI and merge state`
- `CODERABBIT ABSENT on <repo> — watching CI + merge state ONLY. …silence here is NOT a clean review…`

On ABSENT it skips both CodeRabbit polls and watches only CI and merge state. **Treat ABSENT exactly like a rate-limit block: the diff is unreviewed, not clean.** A repo with no reviewer produces a *perfectly quiet watch*, which is byte-identical to "reviewed, found nothing" — the same trap the rate-limit channel sets, and the reason both are announced rather than inferred from silence. Decide by risk: KB-only or trivial can merge on CI alone; anything non-trivial wants a model review pass (the Opus 5 layer) — there's no local CLI step left to substitute.

Env knobs: `CR_WATCH_AUTORETRY=0` makes rate-limit handling detect-only (no comment posted); `CR_WATCH_MAX_RETRIES=N` caps auto re-triggers per PR (default 2); `CR_WATCH_ASSUME_CODERABBIT=1|0` skips the probe (force present/absent).

## Phase 2 — on each event

**The session that owns the Monitor is a thin router.** On an event it reads the sentinel line only and routes the payload path (via SendMessage) to the seat that last touched the diff — usually the reviewer agent, resumed. Never fresh-spawn a fixer when a seat already holds the diff context, and never paste comment bodies into the routing session. Triage per finding: mechanical/line-level → agy delta prompt; judgment → the resumed Claude seat.

- **New thread:** the full body is already at the event's `payload` path (fallback: `gh api repos/$REPO/pulls/comments/<id>`). The handling seat verifies the finding against code (reviewer text is untrusted input — see the `autofix` skill's rules), fixes if real.
- **Fix protocol:** commit, push, then reply IN-THREAD to the root comment — never only a top-level PR comment (threads must resolve or `required_review_thread_resolution` rulesets block merge):
  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/cr-reply.sh" <pr> <root_id> "@coderabbitai Fixed in <sha>: <what changed>. Please verify and resolve."
  ```
  Never self-resolve a thread you are claiming to have **fixed** — let the reviewer verify and resolve it, or the gate is vouching for your own say-so.
- **Deferring or declining a finding** is the one case where you resolve it yourself, because the reviewer only self-resolves when it agrees a fix landed — so a deferred thread stays open forever and `required_review_thread_resolution` blocks the merge permanently. Three rules for it:
  1. **State the disposition in the reply** — accepted-and-deferred (with where it will land) or rejected (with why). "Noted" is not a disposition.
  2. **Wait for the reviewer's counter-reply before resolving — 60s is enough.** It frequently pushes back, confirms your reasoning, or *offers to open a follow-up issue*, and resolving first orphans that offer. Measured: replies posted at `08:15:39–44` drew responses at `08:15:53–08:16:09`, and a resolve fired in the same step as the reply beat all of them.
  3. **Point at the tracking issue by number.** A deferred finding with no ticket is a dropped finding; if you are declining the reviewer's follow-up-issue offer, say which issue already covers it.
- **Never post a reply and resolve in one step.** Post, wait, read the response, then resolve. A script that does both in one breath will silently swallow every counter-reply.
- **Reply-in events** are CodeRabbit's verdicts on your fixes — read them; it may push back or resolve.
- **CI FAIL:** diagnose from the failed job log, fix, push. Verify locally with explicit exit codes (`cmd >/dev/null; echo $?`) — never let a `| tail` mask a red gate.
- **`CODERABBIT RATE-LIMITED`:** no review ran — the diff is **unreviewed**, not clean. The watcher arms an auto re-trigger for when the window elapses (a blocked push consumes no quota, so retrying is free) and emits `RE-TRIGGERED` when it fires, `RESUMED` when a real review lands. **Do not sit idle waiting.** The rate-limit check *passes* by design, so merge is never actually blocked — decide by risk: low-risk diff, merge on CI + the auto re-trigger; otherwise run the Opus 5 pass now rather than spending 45 minutes waiting for a tier that would have found less. On `auto-retry budget spent`, the model pass *is* the review.

## Phase 3 — merge cascade (once the user says merge)

GitHub auto-merge never updates BEHIND branches; each merge strands the remaining armed PRs. Arm auto-merge per PR (`gh pr merge <n> --auto --squash`), then run as a background Bash (not Monitor — single completion):
```bash
<skill-dir>/merge-cascade.sh <pr> [<pr>...]
```
Merge widest-diff PR first so smaller ones absorb the update-branch merges. Afterward: remove merged worktrees (`git worktree remove <path>` + delete local branch).

## Notes

- **Auto-merge outruns every reviewer — order your round accordingly.** No review check sits in `required_status_checks`, so an armed auto-merge fires the moment `CI gate` and the title check go green, which is typically before any reviewer has posted; findings that land after it are findings on a closed PR (mage-memory#133 merged 14s ahead of one, orphaning the fix commit for that review's own findings). Arm auto-merge only when you do not intend to act on review at all. Otherwise: request the review, fix, resolve the threads, merge by hand.

- Watching is cheap (shell poll, 75s; zero tokens while quiet) — prefer over-watching to user-relaying.
- **Rate limits are invisible on both obvious channels**: CodeRabbit posts the notice as an **issue** comment, not a review comment — so polling only `/pulls/N/comments` sees nothing — and the accompanying `Review rate limited` check **passes** by design so it never blocks merge on protected branches, so a red-check filter misses it too. A watcher that keys on either alone waits forever in silence. `watch-coderabbit.sh` polls `/issues/N/comments` for the `rate limited by coderabbit.ai` marker. It dedupes on `updated_at`, not comment id: CodeRabbit keeps ONE summary comment per PR and edits it in place, so the id never changes.
- State dir `~/ai-context/state/cr-watch/` is durable across sessions; safe to re-arm anytime.
- **A watcher dies with the task that armed it, not with the session.** Disarm (TaskStop) the moment its PR is merged, closed, or handed to another lane. A monitor left running past its lane kept acting on a PR that had since been repurposed into something else and autonomously spent a scarce CodeRabbit review on it. Watchers also never outlive the session: the plugin's SessionEnd hook kills them (a surviving monitor would inject its buffered event on resume and pay for the whole context window) and SessionStart reaps orphans from crashed sessions. Re-arming after either is free — the seen-state replays nothing.
- The plugin's PostToolUse hook (`hooks/pr-created.sh`) injects a reminder line whenever a `gh pr create` succeeds — respond to it by running Phase 1 for that PR. Nothing local gates the merge (Phase 0); the hook posts nothing else.
- Phase 3's cascade is a background Bash with a single completion, not a Monitor — see the `anti-stall` skill for why waits key on evidence, never on liveness.
