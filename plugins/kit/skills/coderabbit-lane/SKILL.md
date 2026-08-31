---
name: coderabbit-lane
description: "CodeRabbit review lane (`coderabbitai[bot]`) mechanics: managing the shared org-wide cooldown counter (~1 review per 40 min), manual admission via `coderabbit_review` label, per-repo admission read from the registry, when spending a slot is warranted (.coderabbit.yaml invariants or unshared model check), bare `@coderabbitai review` trigger syntax, the in-thread reply protocol with `cr-reply.sh`, and thread resolution rules. Load when deciding to request CodeRabbit review, handling its feedback threads or rate limits, or replying to `coderabbitai[bot]` comments."
metadata:
  version: "1.1.0"
---

# The CodeRabbit review lane

The CodeRabbit review lane (`coderabbitai[bot]`) is our independent automated reviewer. It runs against pull requests on enabled repositories to catch bugs, design flaws, and violations of repository invariants.

Boundaries: `AGENTS.md` decides reviewer routing; this skill never repeats that choice. `pr-watch` covers watching a PR this session raised, watcher lifecycles, and merge mechanics. `claude-review-lane` covers our `claude[bot]` lane. `autofix` handles applying PR-thread feedback with per-change approval. Process truth lives in `claude-kit/docs/pr-review-process.html`.

## 1. Admission and enablement

Admission is a per-repo setting, so read it rather than assuming: `kit-meta.sh get <repo> coderabbit_auto_review`. The repo's own AGENTS.md carries why it is set that way.

- **Manual admission (`coderabbit_auto_review` false):** Apply the `coderabbit_review` label by hand or post a bare `@coderabbitai review` comment. Without the label, CodeRabbit outputs `Review skipped: excluded by label configuration`, which is expected behavior, not an error.
- **Automatic admission (`auto_review.enabled: true` in that repo's `.coderabbit.yaml`):** Every PR is reviewed with no summon. **The push is the request.** There is no step to withhold, so batch before pushing rather than before triggering, and never instruct a lane to hold off triggering when pushing is what triggers it. A repo hosting `claude-code-review.yml` needs this, because `claude-code-action` self-skips on any PR editing that file, leaving CodeRabbit as its only reviewer.

## 2. When spending a slot is warranted

CodeRabbit review slots are scarce. Spending one is a deliberate budget decision, never a routine step. Spending a slot is warranted in two situations:

1. **Repository invariants:** When the pull request touches paths carrying invariants in that repository's `.coderabbit.yaml` path instructions. Those path instructions are the only channel carrying repository invariants and design decisions into a review, and the Claude lane cannot see them.
2. **Independent validation:** When a Claude finding or a high-risk change wants a check from an independent reviewer sharing no model or failure mode.

Tame reviewer noise with `profile: chill` in `.coderabbit.yaml` and distill key repository constraints into path instructions.

## 3. Shared org-wide cooldown-gated counter

The review lane operates on the Free/OSS plan, where seat assignment is disabled:

| Plan | PR/hr | Files per review |
|---|---|---|
| **OSS** (our public repos) | **1–10** (typically ~1–2) | 50–150 |
| Pro | 5 | 150 |
| Pro+ | 10 | 300 |

- **Org-wide counter:** The counter is shared across all repositories, sessions, and subagents, not per-branch or per-session. A successful review incurs an org-wide cooldown of roughly 40 minutes (budget ≥45 minutes). Run at most one review at a time across the whole organization. Parallel runs serialize and delay all lanes.
- **Every run spends a slot:** Initial reviews, automatic incremental reviews after a push, and manual `@coderabbitai review` comments all spend one slot. To prevent rapid budget exhaustion, enabled repositories set `auto_pause_after_reviewed_commits: 1` in `.coderabbit.yaml`: one review per PR, then batch fixes before re-requesting.
- **Batch fixes before requesting:** Never spend a slot on a commit you are about to amend.
- **Remaining capacity is not readable:** Querying `@coderabbitai rate limit` yields documentation links, never remaining counts. The `waitTime` in rate-limit error messages is the only signal.
- **Cooldown retries:** Retrying 37 minutes after a review is rejected outright without wait times; retries at ≥45 minutes succeed. Budget ≥45 minutes and confirm acceptance.
- **`review full` is NOT a way past the limit.** Both trigger forms draw the same included-review budget, so `review full` does not get past a rate-limit refusal. An apparent success shortly after a refusal is the limit window rolling over, not the command; do not read it as a bypass. Use `review full` when the incremental form refuses because it "does not re-review already reviewed commits", which is a different refusal; use the clock for the limit.
- **CodeRabbit edits its reply in place, so a first read can show the opposite of the settled outcome.** Read the comment's `updated_at`, wait for it to stop changing, and classify on the settled body.

## 4. Trigger grammar and polling

- **Two triggers, both bare.** `@coderabbitai review` is incremental and is the default. `@coderabbit review full` re-reads the whole diff and is the fallback when the incremental one is refused, per §3. The rejection notice names the reason the incremental form gets refused twice over: it is "an incremental review system and does not re-review already reviewed commits", so a push that only moves documentation can be declined even off cooldown.
- **Keep trigger comments bare:** Post exactly the trigger, with nothing else. Comments containing extra questions or bullet points are parsed as chat rather than commands, returning *"For best results, initiate chat on the files or code changes"* with no review executed. Put context in the PR description instead, which the review reads automatically.
- **Poll after every trigger, without exception.** A trigger comment posting successfully is not a review starting. Wait ~60 seconds, inspect the latest `coderabbitai[bot]` comment, and only then report an outcome. Three cases:
  1. `rate limited`: Request rejected, nothing ran. `review full` draws the same budget and will not get past this; wait out the window. See §3.
  2. `initiate chat on the files`: Misparsed as chat; re-trigger with a bare comment.
  3. Anything else: Accepted; review in progress.
- **Analysis depth:** CodeRabbit is not diff-only. Its analysis chains execute `rg`, `fd`, `sed`, `git show`, and inline Python against the repository checkout to reason across files outside the diff. It does not run test suites.

## 5. In-thread reply protocol

Replies to CodeRabbit review comments must go in-thread to satisfy `required_review_thread_resolution` merge requirements:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cr-reply.sh" <pr> <root_id> "@coderabbitai Fixed in <sha>: <what changed>. Please verify."
```

- **Never write the word "resolve" in a reply:** Writing "resolve" causes CodeRabbit to parse the reply as a command and return boilerplate instructions ("Post `@coderabbitai resolve` as a new top-level PR comment"), resolving nothing.
- **Reply-in events:** CodeRabbit posts verdicts on your fixes as replies in the thread. Read them to verify whether it accepted the change or pushed back.

## 6. Thread resolution rules

- **Fixed threads:** Resolution of fixed threads happens via one verified re-review, not blanket commands. After all fixes for the round are committed, pushed, and replied to in-thread, spend one `@coderabbitai review` trigger. CodeRabbit re-evaluates the changes and automatically resolves threads it considers addressed. Any threads left open must be reviewed and resolved individually with rationale stated in-thread.
- **Do not use blanket resolve on fixed threads:** Bare top-level `@coderabbitai resolve` blanket-resolves all threads with zero validation. It is reserved strictly for rounds that consist entirely of declined or deferred findings where dispositions have already been recorded.
- **Declining or deferring findings:** CodeRabbit only self-resolves when it agrees code changed. If declining or deferring a finding, the operator or session resolves it directly under these three rules:
  1. State the disposition clearly in the reply (accepted-and-deferred with landing target, or rejected with reasons; "noted" is not a disposition).
  2. Wait ~60 seconds for CodeRabbit's counter-reply before resolving, ensuring follow-up issue offers or counter-arguments are not dropped.
  3. Reference tracking issues by number.
- **Never reply and resolve in a single step:** Allow time for the reviewer counter-reply before closing the thread.
