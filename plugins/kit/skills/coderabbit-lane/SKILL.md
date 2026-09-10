---
name: coderabbit-lane
description: "CodeRabbit review lane mechanics: the per-developer hourly slot shared across repos, per-repo admission, when a slot is worth spending, trigger syntax, in-thread replies with cr-reply.sh, thread resolution. Load when requesting or answering CodeRabbit."
metadata:
  version: "3.0.0"
---

# The CodeRabbit review lane

`coderabbitai[bot]` is the independent automated reviewer. `AGENTS.md` decides reviewer routing. `pr-watch` covers watching a PR this session raised, watcher lifecycles and merge mechanics. `claude-review-lane` covers `claude[bot]`. `autofix` applies PR-thread feedback with per-change approval. Process truth is `claude-kit/docs/pr-review-process.html`. Stories are in `docs/incidents.md`.

## 1. Admission

Admission is per repo. Read it: `kit-meta.sh get <repo> coderabbit_auto_review`. The repo's own AGENTS.md says why.

- Manual (`coderabbit_auto_review` false): apply the `coderabbit_review` label by hand, or post a bare `@coderabbitai review`. Without the label CodeRabbit outputs `Review skipped: excluded by label configuration`, which is expected.
- Automatic (`auto_review.enabled: true` in that repo's `.coderabbit.yaml`): every PR is reviewed, no summon. The push is the request, so batch before pushing, and never tell a lane to hold off triggering when pushing is what triggers. A repo hosting `claude-code-review.yml` needs this, because `claude-code-action` self-skips on any PR editing that file.

## 2. When a slot is warranted

A slot is a deliberate budget decision, never routine. Two cases:

1. A sensitive surface: the CI and workflow surface itself, credential and crypto handling, the engine core, contract and schema changes.
2. Independent validation: a Claude finding that wants a reviewer sharing no model, prompt or failure mode.

A judgement call, not a path test. prismalens #415 retired `review-admit.yml` and the `review-evidence` gate, and neither file is on `main`; do not propose finishing them (`prismalens-415-retires-automatic-admission`). The hand-applied label is the whole mechanism. Hand admission exists because traffic outruns the counter (`traffic-outruns-counter-measurement`).

`.coderabbit.yaml` path instructions still shape review quality and the Claude lane cannot see them, so they stay worth writing. They do not decide admission. `profile: chill` tames noise.

## 3. The per-developer counter

The lane runs on the Free/OSS plan, seat assignment disabled:

| Plan | PR/hr | Files per review |
|---|---|---|
| Free | 1 | 150 |
| OSS (our public repos) | 1 to 10, typically 1 or 2 | 100 to 300 |
| Team | 8 | 300 |

Essentials was formerly called Pro, and Team was formerly called Pro+.

- **The star count does not tell you whether `auto_review` fires.** Fewer than 10 stars describes the OSS tier's default, and a repo carrying `auto_review: true` gets automatic review anyway. `prismalens/gh-workflows` is public with 0 stars, and `coderabbitai[bot]` posted 8 to 93 seconds after `gh pr create` on `#158`, `#155` and `#142`, all three non-draft, with no human summon first. Settle it per repo by comparing the PR's `createdAt` against the first `coderabbitai[bot]` comment in `repos/<owner>/<repo>/issues/<n>/comments`, never by `stargazerCount`.
- **A draft is exempt, and that decides when to batch.** `reviews.auto_review.drafts` defaults to false, so on a draft the bot posts `Draft PR not reviewed` and stops without spending anything (`prismalens/gh-workflows#161`, 6 seconds after open). Three rules follow. A draft costs nothing to open and nothing to push to. A non-draft spends the slot at `gh pr create`. A draft spends it the moment it is marked ready. So open the draft first, push as often as the work wants, and mark ready once at the end. Holding commits back before the push only saves a slot on a pull request that is already ready.
- **Do not read the plan off the bot.** CodeRabbit's run configuration reports a feature tier, and it printed "Plan: Team" on a repo that is rate-limited as Free, because open-source projects receive Team features without a subscription. The name the bot prints is not the row of the rate-limit table that applies.
- The counter is per developer, not per repo, branch, session or subagent. `prismalens`, `sreforge` and `mage-memory` draw one pool. Run at most one review at a time across every repo you touch; parallel runs serialise and delay every lane.
- Every run spends a slot: initial reviews, automatic incremental reviews after a push, manual `@coderabbitai review`. The label gates automatic review only; a manual summon on an unlabelled PR still spends the counter, which makes it the escape hatch when the Claude lane is down. Enabled repos set `auto_pause_after_reviewed_commits: 1` in `.coderabbit.yaml`: one review per PR, then batch fixes before re-requesting.
- Auto-pause is recoverable. A push past the limit pauses the lane on that PR and nothing arrives on its own. A bare `@coderabbitai resume` restarts it, and what follows is a real review of the final head that posts `Review completed`, so a PR paused by its own fix commits can still meet a merge condition requiring one. Resume deliberately; it spends a slot.
- Batch fixes before requesting. Never spend a slot on a commit you are about to amend.
- Remaining capacity is not readable. `@coderabbitai rate limit` returns documentation links.
- The notice's stated wait is accurate. Obey it, because it is the same one-review-per-developer-per-hour Free limit measured directly, not a guess. It is the per-developer window anchored to the last accepted review, measured exact to within fifteen seconds. A flat 60 minutes from the refusal has the wrong anchor and lands about 21 minutes late (`flat-60-minute-wait-error`). `watch-coderabbit.sh` arms on the parsed figure and falls back to `CR_WATCH_COOLDOWN_SECONDS` (default 3600, a coincidental match to the hourly limit since this is the unparseable-notice fallback, not the limit itself) only when nothing parses; the event line names which it used. CodeRabbit has used at least three wordings, and the pattern once matched only the first (`claude-kit-28-rate-limit-wording-gap`):
  - `Next review available in: **47 minutes**`
  - `**Next included review available in 30 minutes.**`
  - `Your next included review will be available in 23 minutes.`
- The documented limit is one review per developer per hour on Free, rolling. The observed interval between an accepted review and the next runs about 55 to 57 minutes.
- `review full` is not a way past the limit. Both forms draw the same budget. A success shortly after a refusal is the window rolling over. `review full` is for the different refusal, "does not re-review already reviewed commits"; the clock is for the limit.
- CodeRabbit edits its reply in place, so a first read can show the opposite of the settled outcome. Read `updated_at`, wait for it to stop changing, classify on the settled body, and re-read before acting, not only before classifying (`settled-body-classification-trap`).

## 4. Triggers and polling

- Two triggers, both bare. `@coderabbitai review` is incremental and the default. `@coderabbit review full` re-reads the whole diff and is the fallback when the incremental form is refused as "an incremental review system" that "does not re-review already reviewed commits"; a push that only moves documentation can be declined off cooldown.
- Post exactly the trigger and nothing else. Extra questions or bullets are parsed as chat, return "For best results, initiate chat on the files or code changes", and run no review. Context goes in the PR description, which the review reads.
- Poll after every trigger. A trigger posting is not a review starting. Wait about 60 seconds, inspect the latest `coderabbitai[bot]` comment, then report. `rate limited`: rejected, nothing ran, wait out the window. `initiate chat on the files`: misparsed, re-trigger bare. Anything else: accepted.
- CodeRabbit is not diff-only. It runs `rg`, `fd`, `sed`, `git show` and inline Python against the checkout to reason across files. It does not run test suites.

## 5. In-thread replies

Replies go in-thread, to satisfy `required_review_thread_resolution`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cr-reply.sh" <pr> <root_id> "@coderabbitai Fixed in <sha>: <what changed>. Please verify."
```

- Never write the word "resolve" in a reply. CodeRabbit parses it as a command and returns boilerplate ("Post `@coderabbitai resolve` as a new top-level PR comment"), resolving nothing.
- Reply-in events are CodeRabbit's verdicts on your fixes. Read them.

## 6. Thread resolution

- Fixed threads resolve through one verified re-review, never a blanket command. After every fix for the round is committed, pushed and replied to in-thread, spend one `@coderabbitai review`. CodeRabbit resolves the threads it considers addressed; anything left open is reviewed and resolved individually with rationale in-thread.
- Bare top-level `@coderabbitai resolve` blanket-resolves every thread with zero validation. Reserved for rounds made entirely of declined or deferred findings whose dispositions are already recorded.
- Declining or deferring: CodeRabbit self-resolves only when code changed, so the operator or session resolves under three rules. State the disposition (accepted-and-deferred with landing target, or rejected with reasons; "noted" is not a disposition). Wait about 60 seconds for the counter-reply so follow-up issue offers are not dropped. Reference tracking issues by number.
- Never reply and resolve in one step.
