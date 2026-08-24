---
name: unattended-run
description: "Rules for holding a long unattended run — organizer discipline, lane count from the scarce resource, stall detection, evidence-not-green, verify-every-claim, park-don't-decide. Load BEFORE starting any session where the operator is away or unreachable and the work is expected to outlast their attention — an overnight run, a multi-hour delegation, a cron-driven organizer's first wake-up — and whenever a dispatched lane reports \"standing by\"."
metadata:
  version: "1.3.0"
---

# Unattended run: holding a long autonomous session

One seat holds the goal across many wake-ups; every other seat is disposable. Everything below is a failure that has already cost hours of an unattended window, stated as the mechanism rather than the prohibition. Prose alone does not prevent the stall (§4).

Companion skills, assumed and not repeated: **`anti-stall`** (how a wait is built), **`agy-delegate`** (how a cheap executor is driven), **`pr-watch`** (per-PR lifecycle).

## 0. The plan file is the session's memory

One file, `~/ai-context/<repo>-<task>-plan.md`, is the source of truth. It survives compaction, cron wake-ups, and the operator's return; chat scrollback survives none of those. It carries: standing rules, a lane table with live state, decisions waiting on the operator, verified environment facts, and a running log. Detail goes there, not into the terminal (§11).

At hand-off, before the operator leaves, record: what is scarce, which repos and worktrees exist, what is frozen, and what must never be merged.

**If the file does not exist yet, building it is the whole first tick and nothing is dispatched until it does:** enumerate the queue read-only, group it into waves by what blocks what, name the scarce resource (§2), and probe the environment rather than assuming it (which stacks are up, which worktrees exist, which repo owns which name). Then write the standing rules down, including the ones the operator gave verbally.

**Respect the window.** Never start a lane that cannot both finish *and* be verified inside the time remaining; as the boundary approaches, only take work to a state that is safe to leave, meaning pushed, commented, or parked, never mid-merge or mid-rebase.

## 1. The organizer never edits repo files

Dispatch and judge. Editing a file means the seat that holds the whole goal spent its turn on work a cheap lane could have done, and stopped tracking every other lane while it did. The organizer's only outputs are dispatches, verdicts on returned claims, plan-file updates, and merges.

Lanes work in worktrees, never in the main checkout. `AGENTS.md` fixes which mechanism, and a Claude subagent lane and an agy lane do not get the same one. The main checkout and the stack it serves are the organizer's, and a lane that "restores" its branch takes the whole run down with it. The organizer creates or reuses the worktree; the lane is handed an absolute path and told to stop and report if it is missing.

**Every dispatch prompt carries, explicitly:** the absolute worktree path · the exact verify commands and the expectation that the lane runs them itself · the report format (findings, evidence, SHAs, blockers, no prose) · the stop conditions ("abort and report rather than improvise" on any conflict, any frozen path, any gate still red after N minutes) · what the lane may **not** do (merge, close, bypass, edit a frozen path) · the stall rule (§4).

Never override a delegate's brief with reasoning invented on the spot. Incident: an organizer ordered a lane to spend the run's last unit of a scarce counter on an action its own brief had already named a guaranteed-empty burn, backed by a plausible but sourceless claim. The lane refused, correctly. If you contradict a delegate's brief, cite the source that supersedes it; with no source, the brief wins.

## 2. Lane count is a function of the scarce resource, not a constant

There is no correct number of lanes. Each run names its own limit from whatever is actually scarce and writes it in the plan file. Two kinds recur:

- **A shared external counter.** One org-wide review counter with a cooldown means one review in flight across the whole org; parallel lanes do not parallelise it, they serialise behind it and slow every lane.
- **A serialising invariant.** Merges to one branch re-BEHIND every other PR (§7), so merging is one-at-a-time regardless of how many lanes exist.

Name the resource's **scope**, not just its existence, before parallelising. A limit assumed per-repo can turn out to be org-wide. Incident: a review counter turned out to be per-developer, not per-repo. Three repos drew on the same pool, work queued as independent was actually in contention, and a spend on one repo starved another. State the resource and its scope explicitly in the plan file; serialise everything inside that scope.

Everything not contending on a named scarce resource may run wide.

**Workflows and subagents may be used freely. Cost is the only constraint.** Do not ration agents to save money, and do not do work by hand to avoid spawning one. That trades the expensive seat's attention for the cheap resource. Ration only against a named scarcity.

## 3. Delegate-then-verify

Route bulk reading, log triage, rebases, evidence collection and repetitive per-PR procedure to the cheap executor. **Never let its claims reach an artifact unverified.** A drafting pass on PR bodies once fabricated a UI button label and attributed a screenshot to the wrong route. Both were plausible, neither was detectable from the draft, and cross-checking component source at the head SHA caught both. Cheap models gather and draft; verification belongs to the organizer or a Claude handler, always against source at the exact SHA.

Judgment-heavy work skips the cheap lane entirely: security/crypto, design surface, product semantics.

## 4. The stall rule: a wait must hold the turn

**An agent that returns saying "standing by", "waiting for", or "will be notified" has stalled. It is not waiting.**

The mechanism: a completion notification fires only when an agent has **no live background children**. The moment an agent launches something in the background and returns control, that notification can never arrive. Returning guaranteed nothing is watching. It recurs across independent lanes even where the doctrine is already written down. That makes it a designed-in hazard, not an agent-quality problem.

- A wait is valid **only while the agent is still executing inside its own turn**: a foreground `until` loop keyed on durable evidence, loop length as the deadline (`anti-stall` §2).
- A background launch followed by a return of control is a stall, always.

**Resume action, immediately, without acknowledging the report:** `SendMessage` to that agent: "go read <the concrete artifact: log path, PR check, SHA> now; then wait in the foreground with a deadline; do not return until the evidence resolves or the deadline expires." Never accept two consecutive "waiting" reports; read the artifact yourself instead.

Every dispatch prompt carries this rule. Assume the lane will otherwise walk into it.

**The mirror failure: a watch that outlives its task.** A monitor, a poller, a cron tick. Anything armed to watch one piece of work is torn down the moment that work ends: merged, closed, reassigned, or abandoned. One left standing kept acting on a PR that had since been repurposed into something else, and autonomously spent a scarce shared counter on it. Arming something durable creates a teardown obligation in the same breath; record it in the plan file's lane table beside the thing it watches, and disarm as part of closing the lane.

## 5. A green job is never evidence, only a posted artifact is

A workflow can report `success` having posted nothing, and does. A reviewing lane reported success while posting no review at all for two weeks; every status-only read of it said the PR had been reviewed.

- Check the **producing** job, not the wrapper check. A green review step means the lane ran; only the artifact it was supposed to post counts.
- A green gate whose description names a **retired producer** is a stale artifact, not a pass. It flips red the instant anything re-evaluates it, and a status-only read cannot see that coming.
- Independent triage lanes read exactly that stale green as real and called the PR "clean, ready to merge". Two of them, separately. Hence §8.

## 6. Changing enforcement machinery: settings first, and only if it must exist

A gate is a subsystem, and when it is wrong it is wrong for the whole repo. Six PRs in one series each had to pass the very check they were repairing, so every bug in it became a repo-wide merge outage.

- **Ask "should this exist?" first, not fourth.** Consult per subsystem, not per hole: four adjudications on one gate were each locally sound and globally wrong, because whether the gate should exist at all was asked after all four had landed.
- **Prefer a native platform feature to a workflow that emulates one.** That gate was a hand-built re-implementation of `required_review_thread_resolution`, which was already switched on in the same ruleset.
- **Never write predicates over a vendor's artifacts**: comment bodies, review states, marker strings, walkthrough stubs. None is a documented contract, and all are summonable by anyone who can leave a comment. Tightening a parser of an adversarial, unversioned grammar does not terminate; it relocates the hole. Five sound fixes produced five holes in the same place. Where a control is genuinely needed, prefer a **capability boundary**, a tool the agent does not have, over a grammar.
- **Size the control to the asset.** Single-tenant, dev-phase, no outside contributors, and an adversary model of a drifted agent holding the maintainer's credential. That is the same credential that administers the ruleset, so it defeats any in-repo gate by construction. A control that cannot bind its own adversary costs without buying.
- **Fail-closed is for security decisions, not for plumbing.** Pointed at an unreliable evaluator it manufactures outages: an unreadable policy file classified *every* PR as high-risk, turning one file-path bug into a repo-wide merge block.
- **Enforcement changes are settings-first.** Rulesets are API-editable, atomically, with no PR. Flip the setting, then land the code that matches it. Never ship a change whose own merge depends on the thing it is changing.
- **No check enters `required_status_checks` until one live PR has passed through it happy-path, observed.** That gate went required before a single clean PR had greened through its intended path, and the path turned out to be unable to fire at all.
- **Product PRs never wait on gate PRs.** The gate series is its own lane; queue product work behind it and one subsystem's outage becomes the whole run's.

## 7. One merge in flight; cascade by hand

> **Queue-era scope note (prismalens#403):** on merge-queue repos
> (`kit-meta.sh get <repo> merge_queue` → true; today prismalens and sreforge) the
> cascade mechanics below are OBSOLETE. The queue tests a speculative merge, so
> merges neither strand siblings nor need serialising, and `gh pr merge` enqueues.
> What survives unchanged is the race: **the queue gates on checks and threads, not
> on whether a reviewer has spoken.** Unattended rule on queue repos: enqueue only
> after the PR's liveness comment reports posted review output; otherwise report
> ready and leave it (§10). A liveness comment reading *auto-paused* is not review
> evidence. The lane declined this head, so summon `@claude review` and get a posted
> review before enqueueing. Classic repos (mage-memory) still follow everything below.

**Never arm auto-merge while reviewers are advisory-only.** When no review-related check is required, auto-merge fires the instant CI is green, routinely *before* the reviewer has finished. Measured on prismalens#388 at `2bcdbcaf`: `CI gate` ran 05:42:58→05:43:01 while the `review` job ran 05:40:58→05:43:42, so the merge condition was satisfiable **41 seconds ahead of the reviewer**. The findings then land on an already-merged PR, `required_review_thread_resolution` gets nothing to block on, and review enforcement is exactly zero. Until a review-related requirement exists for auto-merge to wait on, whether a required approving review or the review job itself as a required check, **merges are attended.**

The corollary for an unattended run: an orchestrator that cannot merge attended does **not** arm auto-merge instead. It takes the PR to green, reports it ready, and leaves the merge to the operator (§10).

The exit from the constraint, under active consideration and not settled: `required_approving_review_count: 1` satisfied by a job that submits the approval after the reviewer has run, with the **token held by the job, never by the reviewing agent**. That agent reads attacker-controlled diff content, so a prompt injection would otherwise become a self-approval.

Every merge re-BEHINDs every other open PR, and auto-merge never updates a BEHIND branch.

- Serial merges only, one at a time, verifying the gate after each.
- Cascade manually: after each merge, update the next branch, wait for its required checks to re-green on the new base, then merge.
- When PRs contend on one shared file (a lockfile, a generated artifact), land the smallest delta first; each landing forces a regenerate on the rest.
- With no scheduled sweeper, a PR that merely goes BEHIND fires **nothing**. Its status sits stale indefinitely. Staleness is silent; go look.
- Rebase the PRs you are deliberately parking at the **end** of the drain. Rebasing them early only re-BEHINDs them behind every subsequent merge.

## 8. Verify every delegate claim against live state

A returned report is a hypothesis. Before it changes a decision, confirm it against the thing itself: the head SHA, the check's description string, the job log, the file at that SHA. A diff claimed as one line gets read. Two independent lanes agreeing raises no confidence. They can share one stale input, and did.

A PR body that claims what the PR does **not** do gets checked against the file list, not taken on faith. A body stating two scripts would be kept, whose diff deleted them, was merged with the deletions on screen. Cheap to check; body/diff divergence is invisible afterward.

## 9. Never bypass a ruleset or a gate

When a gate blocks the only available fix, **escalate; do not override.** Waiting out a cooldown inside an eight-hour window is cheap; a bypass is unrecoverable.

First tell a gate that is **failing** (retrying is right) from one that is **unsatisfiable** (retrying burns the run's remaining time for nothing). Incident: a required check demanded a reviewer artifact the reviewer only emits when it has findings. A correct, trivial change could never produce that evidence, so the fix for the gate could not pass the gate. The tell: the same action produces the same empty result twice, with no error. On the second identical empty result, stop and escalate; do not try a third.

The reasoning that makes this bite: the PR that *repairs* the gate is the **worst** candidate in the repo for skipping review. Every independent-reviewer catch on that track landed in exactly that territory, **including ones the adjudicating model had already ruled acceptable.** A gate change reviewed only by the model that wrote it is precisely the failure independent review exists to prevent (§6).

- A **conditional** pre-authorization ("this might need a bypass") is a reserve, not an instruction. Write down the exact condition that would spend it, and do not spend it for mere slowness.
- Never reach for a skip flag, an `--admin` merge, a `--no-verify` push, or a ruleset edit. If a lane already used one, record it and stop that lane; do not quietly bank the result.
- Dilemma → consult the planner seat: a fresh agent on the strongest planning model, given the decision, the constraints, and the options, not the whole run. Frame the consult around the **subsystem**, not the hole in front of you (§6). If the last consult is more than an hour old, start a new one rather than resuming it; a stale consult reasons from premises the run has since disproved. Its ruling is binding for that decision, and its explicit deferrals stay deferred.

## 10. Park anything needing operator sign-off

- Work that changes what the operator sees or owns goes **to green and stops**: UX shape, exported API, architecture naming, scope. Never merge it.
- Diverged, superseded or obsolete PRs get a **comment** stating the state, and stay open. Never close one. "Obsolete" is a judgement the operator makes, not you: a PR qualifies for the comment-and-leave treatment when its own body reclassifies it out of the current scope, when it carries an unresolved question only the operator can settle, or when its diff no longer applies to the current base for reasons other than a mechanical rebase. Age alone is not divergence.
- An honest gap beats a fabricated claim: where the evidence for a parked item is incomplete, say so in the artifact itself.
- Every parked item lands in the plan file's decisions list as a specific question with options, not "needs review".

## 11. Terse output: the operator reads a terminal

Findings, decisions, evidence, SHAs, blockers. No restating the plan, no narrating what is about to happen, no re-summarising work already logged. Every dispatched agent gets the same instruction. **A tick with no dispatch is a valid tick**, one line with the reason.

A report leads with what **landed**, the SHAs of anything merged or pushed, before what is pending. Incident: a lane merged the first PR of an eight-hour run, then reported only that it was waiting on a cooldown. The organizer learned about the merge only by checking independently. Silence about a completed step reads as "did not happen" and costs a verification round.

A delegate that refuses an unsourced instruction to spend a one-shot resource is behaving correctly, not insubordinately (§1). Say so in the report rather than treating the refusal as a failure to complete the dispatch.

## Wake-up checklist (each cron tick)

1. Read the plan file first. It, not memory, holds the state.
2. Confirm every lane is **alive** by enumerating agents; never assume. Any lane reporting "standing by" → §4 resume, before anything else.
3. Check real state, not reports: default-branch SHA, each PR's head SHA, each gate's description string.
4. Re-verify the scarce resource's availability (§2) before spending it.
5. Dispatch only work whose prerequisites are final. Starting a lane that depends on an in-flight template means writing it twice.
6. Append findings and decisions to the plan file; one or two lines to the terminal.

Hand back on a hard blocker or the natural end of all work, not on a timer: land any end-of-session deliverable the operator asked for, then leave the plan file's decisions list as the first thing they read. Each entry is a question, its options, and what it blocks.
