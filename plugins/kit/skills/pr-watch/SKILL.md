---
name: pr-watch
description: "Watch a PR raised in this session until its review round completes: seed seen-state, arm the reviewer and CI Monitor, route each event to the seat holding the diff, then merge. Load after any gh pr create or when asked to watch or merge a PR."
metadata:
  version: "4.3.0"
---

# PR watch: the session-scoped review round

One PR, raised in this session, watched until its round ends, so the session reacts to findings without the user relaying them. Not a lifecycle manager: the merge queue removed cascade shepherding, and a PR left over from an earlier session needs no local watcher because GitHub notifications cover verify-then-resolve and enqueue.

Reviewer behaviour lives elsewhere. `claude-review-lane` owns `claude[bot]`, `coderabbit-lane` owns `coderabbitai[bot]`, and both load on a PR of any age. Load the owning skill before acting on that reviewer. The trigger syntax and `cr-reply.sh` appear below so a router recognises them; the preconditions (cooldown arithmetic, budget, the post-trigger poll) live only there, and acting on the fragments produces confidently wrong reports.

Process truth is `claude-kit/docs/pr-review-process.html`. Whoever changes the process updates that page in the same session.

Reviews arrive on their own schedule: the Claude lane in 2 to 5 minutes, CodeRabbit in 3 to 5 after admission, CI in 5 to 10. Never poll with model turns. Never wait for the user to relay an event. Arm a deterministic watcher and process deltas.

Scripts sit in `${CLAUDE_PLUGIN_ROOT}/skills/pr-watch/` when loaded as `kit:pr-watch`; shared ones (`cr-reply.sh`, `kit-meta.sh`) in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Resolve both to absolute paths before handing them to a Monitor or a background Bash, which may not inherit the variable. Watch scripts read the repo off the cwd's origin remote; `--repo owner/name` overrides.

Per-repo facts come from the registry, never from memory. `kit-meta.sh current` reads `data/repo-meta.json` folded with runtime observations:

Current repo metadata: !`"${CLAUDE_PLUGIN_ROOT}/scripts/kit-meta.sh" current`

## Phase 0: the merge contract

Whether anything is enforced is a per-repo fact. `kit-meta.sh get <owner/repo> enforced` answers without a network call. `false` means we checked and nothing is enforced, so holding the PR for the operator is the only gate. "No such key" means we never looked. Read enforcement off `rulesets`; a 404 from `branches/<b>/protection` proves nothing, because a repo on rulesets returns 404 there either way.

Where a repo enforces, the contract is three facts:

- Two required checks, `CI gate` and `Validate PR title (conventional commits)`. Nothing else. No review check, evidence artifact, marker job, SHA pinning, carry-forward or committed high-risk path list. `cr-preview.sh` and `cr-evidence.sh` do not exist.
- `required_review_thread_resolution: true`. One unresolved thread blocks the merge. This is the only thing that enforces a finding, which is what makes Phase 2's in-thread protocol load-bearing.
- Reviewers are advisory. No check waits on them, so no check proves a review happened. What counts as evidence is in `claude-review-lane`.

Push freely; nothing runs pre-push. Escalate by risk, and never pay model tokens for review a cheaper layer already covers:

| Tier | When | What |
|---|---|---|
| Claude review (`claude[bot]`) | Where `kit-meta.sh get <repo> claude_lane` says the lane runs: every same-repo PR, automatic, but not every round and not every author | The default. Inline findings. Advisory, but every thread it opens blocks. See `claude-review-lane` |
| CodeRabbit (`coderabbitai[bot]`) | Per repo: `coderabbit_review` label or `@coderabbitai review` by hand, or automatic where `kit-meta.sh get <repo> coderabbit_auto_review` is true | The independent lane, drawing a scarce per-developer counter. See `coderabbit-lane` |
| One Opus 5 pass | Non-trivial PRs | Spec and ADR conformance, which the bots cannot see |
| `/code-review ultra` | Rare | Engine core, security boundary, contract or schema changes |

Never bypass the ruleset. Batch every fix before you push, not merely before you summon: a CodeRabbit slot spent on a commit you are about to amend is wasted. Where admission is automatic, the push is the request and there is no summon step to hold back; a lane cannot obey "don't trigger CodeRabbit" by pushing. `auto_pause_after_reviewed_commits: 1` limits the damage: the first push spends a slot, later pushes auto-pause and surface as `CODERABBIT AUTO-PAUSED`. Check `coderabbit_auto_review` before assuming you have a summon step (`coderabbit-lane` §1 and §3).

## Phase 1: arm the watcher as soon as a PR this session caused exists

The trigger is a PR existing that this session caused, whoever typed the command: a delegated lane, an agy run or a subagent in its own worktree can open it.

Choose the watcher first. `/autofix-pr` on the PR branch spawns a cloud session subscribed to that PR; it fixes CI failures and review comments and replies in the threads under your account, and this session holds nothing. That is the default. The Monitor below is for a round this session must hold: the fix belongs in a seat that already has the diff, or CodeRabbit's rate limit needs tracking, which auto-fix does not see. Read from code.claude.com/docs/en/claude-code-on-the-web, "Auto-fix pull requests".

Seed the seen-state first, both files, so existing comments never replay as `NEW`:

```bash
mkdir -p ~/ai-context/state/cr-watch
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner); KEY=${REPO//\//-}
C=$(mktemp); trap 'rm -f "$C"' EXIT
gh api "repos/$REPO/pulls/<pr>/comments?per_page=100" > "$C"
jq -r '.[] | select(.user.login|test("coderabbit")) | .id' "$C" \
  > ~/ai-context/state/cr-watch/$KEY-pr<pr>.seen
jq -r '.[] | select(.user.login|test("claude";"i")) | .id' "$C" \
  > ~/ai-context/state/cr-watch/$KEY-pr<pr>-claude.seen
```

Then arm the Monitor tool with `persistent: true`:

```
command: <skill-dir>/watch-coderabbit.sh <pr> [<pr>...]
description: CodeRabbit comments + CI reds on PR <pr>
```

One monitor covers many PRs. If one is already running for this repo, TaskStop it and re-arm with the combined list; seen-state makes that free.

Event lines and what each one asks for are in `references/events.md` beside this file; read it when the first line arrives, not before.

The first line is the presence verdict, `CODERABBIT ACTIVE on <repo> — watching reviews, rate limits, CI and merge state` or `CODERABBIT ABSENT on <repo> — watching CI + merge state ONLY`. `kit-meta.sh get <owner/repo> coderabbit` is the source of truth; the watcher checks it, then probes for a committed `.coderabbit.yaml` or `.yml`, then for a `coderabbit*` author in recent comments, and writes a positive probe back to the registry. ABSENT skips the CodeRabbit polls and means unreviewed, exactly like a rate limit: a repo with no reviewer produces a quiet watch that is byte-identical to "reviewed, found nothing". Decide by risk: trivial or knowledge-base-only merges on CI alone, anything else wants the Opus 5 pass, and no local CLI step substitutes.

Env knobs: `CR_WATCH_AUTORETRY=0` makes rate-limit handling detect-only, posting no comment. `CR_WATCH_MAX_RETRIES=N` caps auto re-triggers per PR, default 2. `CR_WATCH_ASSUME_CODERABBIT=1|0` skips the probe.

## Phase 2: on each event

The session that owns the Monitor is a thin router. Read the sentinel line, then SendMessage the payload path to the seat that last touched the diff, usually the reviewer agent, resumed. Never fresh-spawn a fixer when a seat already holds the diff. Never paste a comment body into the routing session. Triage per finding: line-level goes to an agy delta prompt, judgement to the resumed Claude seat.

Per-event handling is in `references/events.md`.

ery reviewer. The thread gate only blocks once a thread exists, and auto-merge can fire between a review landing and its fix commit. Order the round as review posted, then fix, then resolve, then merge, never the reverse. On queue repos "review posted" is read off the liveness comment.
- Never wait on `mergeStateStatus`. An unresolved thread pins it at `BLOCKED`. Key on `reviewThreads` and comment IDs (`anti-stall` §3).
- Watching is cheap: a shell poll every 75 seconds, zero tokens while quiet. Prefer over-watching to relaying.
- Rate limits are invisible on both obvious channels. CodeRabbit posts the notice as an issue comment, so `/pulls/N/comments` misses it, and the `Review rate limited` check passes by design. `watch-coderabbit.sh` polls `/issues/N/comments` for the `rate limited by coderabbit.ai` marker, deduped on `updated_at` because CodeRabbit edits one summary comment in place.
- `~/ai-context/state/cr-watch/` is durable across sessions. Re-arming is always safe.
- A `git checkout` under a running watcher kills it. Bash reads a script incrementally, so switching branches rewrites `watch-coderabbit.sh` beneath the running shell, usually exit 144, with no event. Re-arm after any branch change, or run the watcher from a path that is not moving.
- A watcher dies with its task, not the session. TaskStop it the moment its PR is merged, closed or handed off. The SessionEnd hook also kills watchers and SessionStart reaps orphans; re-arming after either is free.
- `hooks/pr-created.sh` injects a reminder whenever a PR URL appears in a Bash or Agent tool result, and seeds the seen-state. Answer it by running Phase 1. It is a net, not a guarantee: an agy lane redirects output to a file, so the URL reaches no Bash result and arrives later in the handler's report, which is why the hook also runs on `Agent`. When you dispatch work that ends in a PR, expect the URL in the handler's report (`agy-delegate` babysit step 9) and arm on it.
- Phase 3's cascade is a background Bash with a single completion, not a Monitor.
