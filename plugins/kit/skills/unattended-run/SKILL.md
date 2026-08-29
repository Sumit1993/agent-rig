---
name: unattended-run
description: "Rules for holding a long unattended run: arm the wake-up first, keep the organizer out of the files, size lane count to whatever is scarce, catch stalls, treat a green check as nothing, verify every delegate claim, park what needs a human. Load BEFORE any session where the operator is away and the work will outlast their attention: an overnight run, a multi-hour delegation, a cron-driven organizer's first wake-up. Also load whenever a lane reports \"standing by\"."
metadata:
  version: "2.0.0"
---

# Unattended run: holding a long autonomous session

One seat holds the goal across every wake-up. Every other seat is disposable.

Each rule below comes from a failure that already cost hours of a real unattended window, so each is written as the mechanism rather than the ban. Writing a rule down does not stop it being broken (§4).

Assumed here and not repeated: **`anti-stall`** for how a wait is built, **`agy-delegate`** for driving the cheap executor, **`pr-watch`** for one PR's lifecycle.

## 0. The first tick: arm the wake-up, then write the plan file

These two are the whole first tick. Nothing else is dispatched until both exist, because they are what makes every later tick happen at all.

### Arm the wake-up

With no scheduled wake-up the run is one turn long.

1. `CronCreate` is a deferred tool, so its schema is not loaded. Fetch it first:
   `ToolSearch("select:CronCreate,CronList,CronDelete")`. Nothing in the tool list prompts you
   to, which is why this step gets skipped.
2. **30 minutes is the default.** Set it off the :00 and :30 marks, because every scheduled
   job on the planet lands there: `7,37 * * * *`. Go longer when the thing you are waiting on
   moves slower, and never shorter than the scarce resource's cooldown (§2).
3. The prompt fires into **this** session, so the context is still here. It asks for current
   state rather than restating the run: "tick: read the plan file, check lane and PR state,
   then dispatch or report."
4. `CronList` straight after, to confirm it armed. A cron that failed to arm looks identical
   to a run that is quietly working.
5. Put the job ID in the plan file next to the condition that ends it (§4).

Three facts about `CronCreate` change how the run is planned:

- **Jobs live in this session's memory only.** If the session ends, the cron goes with it and
  the run stops. The plan file still reads healthy, so nothing announces this.
- **Jobs fire only while the REPL is idle.** A long foreground wait (`anti-stall` §2) holds
  the turn and blocks the tick. Keep foreground waits shorter than one tick.
- **Recurring jobs expire after 7 days.** They fire one last time, then delete themselves.

`ScheduleWakeup` paces `/loop` from inside a session and is not this. Use `CronCreate`.

### Write the plan file

One file, `~/ai-context/<repo>-<task>-plan.md`, is the source of truth. A tick fires into this session, so scrollback usually survives a wake-up. It does not survive compaction, a crash, or the operator picking the run up in a new session. The plan file survives all three. It holds the standing rules, a lane table with live state, the decisions waiting on the operator, verified facts about the environment, and a running log. Detail belongs here, not in the terminal (§11).

Before the operator leaves, record what is scarce, which repos and worktrees exist, what is frozen, and what must never be merged.

If the file does not exist yet, building it is the rest of the first tick. Read the queue without touching anything, group it into waves by what blocks what, name the scarce resource (§2), and probe the environment instead of assuming it: which stacks are up, which worktrees exist, which repo owns which name. Then write down the standing rules, including the ones the operator only said out loud.

**Respect the window.** Never start a lane that cannot finish *and* be verified in the time left. As the end approaches, only take work to a state that is safe to leave: pushed, commented, or parked. Never mid-merge or mid-rebase.

## 1. The organizer never edits repo files

Dispatch and judge. Editing a file means the seat holding the whole goal spent its turn on work a cheap lane could have done, and stopped watching every other lane while it did. The organizer produces dispatches, verdicts on returned claims, plan file updates, and merges. Nothing else.

Lanes work in worktrees, never in the main checkout. `AGENTS.md` sets which mechanism, and a Claude subagent lane and an agy lane do not get the same one. The main checkout and its stack belong to the organizer. A lane that helpfully "restores" its branch takes the run down with it. The organizer creates or reuses the worktree and hands the lane an absolute path, with instructions to stop and report if it is missing.

**Every dispatch prompt says, in as many words:** the absolute worktree path, the exact verify commands and that the lane runs them itself, the report format (findings, evidence, SHAs, blockers, no prose), the stop conditions ("abort and report rather than improvise" on any conflict, any frozen path, any gate still red after N minutes), what the lane may **not** do (merge, close, bypass, edit a frozen path), and the stall rule (§4).

Never override a lane's brief with reasoning you invented on the spot. One organizer ordered a lane to spend the run's last unit of a scarce counter on an action the lane's own brief had already called a guaranteed waste, backed by a claim that sounded right and had no source. The lane refused, correctly. If you contradict a brief, cite what supersedes it. With no source, the brief wins.

## 2. Lane count comes from whatever is scarce, not from a number you like

There is no right number of lanes. Each run works out its own limit from what is actually scarce and writes it in the plan file. Two kinds keep coming up:

- **A shared external counter.** One org-wide review counter with a cooldown means one review in flight across the whole org. Extra lanes do not parallelise that. They queue behind it and slow each other down.
- **Something that only works one at a time.** Merges to one branch put every other PR behind the base again (§7), so merging is serial no matter how many lanes exist.

Name the resource's **scope**, not just its existence, before running things in parallel. A limit you assumed was per-repo can turn out to be org-wide. One review counter turned out to be per-developer rather than per-repo: three repos drew on one pool, work planned as independent was actually in contention, and spending on one repo starved another. Write the resource and its scope in the plan file, then serialise everything inside that scope.

Anything not competing for a named scarce resource can run as wide as you like.

**Workflows and subagents are free to use. Cost is the only limit.** Do not ration agents to save money and do not do work by hand to avoid spawning one. That trades the expensive seat's attention for the cheap resource. Ration only against a scarcity you have named.

## 3. Delegate, then verify

Send bulk reading, log triage, rebases, evidence gathering and repetitive per-PR work to the cheap executor. **Never let its claims reach an artifact unchecked.** One drafting pass on PR bodies invented a UI button label and credited a screenshot to the wrong route. Both read as plausible, neither was visible in the draft, and checking the component source at the head SHA caught both. Cheap models gather and draft. Verification belongs to the organizer or a Claude handler, always against source at the exact SHA.

Judgment work skips the cheap lane entirely: security and crypto, anything users see, product semantics.

## 4. The stall rule: a wait has to hold the turn

**A lane that returns saying "standing by", "waiting for" or "will be notified" has stalled. It is not waiting.**

Here is why. A completion notification fires only when an agent has **no live background children**. The moment an agent launches something in the background and hands control back, that notification can never arrive. Returning guaranteed that nothing is watching. This keeps happening in lanes that were handed the rule, so treat it as a trap built into the tooling rather than a bad agent.

- A wait is real **only while the agent is still running inside its own turn**: a foreground `until` loop keyed on durable evidence, with the loop length as the deadline (`anti-stall` §2).
- A background launch followed by handing control back is a stall, every time.

**Fix it immediately and skip the acknowledgement.** `SendMessage` to that lane: "go read <the concrete artifact: log path, PR check, SHA> now, then wait in the foreground with a deadline, and do not return until the evidence resolves or the deadline expires." Never accept two "waiting" reports in a row. Read the artifact yourself instead.

Put this rule in every dispatch prompt. Assume the lane walks into it otherwise.

**The reverse failure: a watch that outlives its job.** A monitor, a poller, a cron tick. Anything armed to watch one piece of work gets torn down the moment that work ends, whether it merged, closed, moved, or was abandoned. One left running kept acting on a PR that had since been repurposed into something else, and spent a scarce shared counter on it unprompted. Arming something durable creates a teardown obligation in the same breath. Record it in the plan file's lane table beside the thing it watches, and disarm it as part of closing the lane.

## 5. A green job proves nothing. Only a posted artifact does

A workflow can report `success` having posted nothing at all, and does. One reviewing lane reported success while posting no review for two weeks. Every status-only read of it said the PR had been reviewed.

- Read the job that **produces** the artifact, not the wrapper check. A green review step means the lane ran. Only the thing it was supposed to post counts.
- A green gate whose description names a **retired producer** is a leftover, not a pass. It flips red the moment anything re-evaluates it, and a status-only read cannot see that coming.
- Two separate triage lanes read exactly that stale green as real and called the PR clean and ready to merge. Hence §8.

## 6. Changing enforcement machinery: settings first, and only if it needs to exist

A gate is a subsystem, and a wrong one is wrong for the whole repo. Six PRs in one series each had to pass the very check they were repairing, so every bug in it became a repo-wide merge outage.

- **Ask "should this exist at all?" first, not fourth.** Decide per subsystem, not per hole. Four rulings on one gate were each locally sound and collectively wrong, because nobody asked whether the gate should exist until all four had landed.
- **Prefer a built-in platform feature to a workflow imitating one.** That gate was a hand-built copy of `required_review_thread_resolution`, which was already switched on in the same ruleset.
- **Never write checks over a vendor's text**: comment bodies, review states, marker strings, walkthrough stubs. None of it is a documented contract, the vendor can change it any time, and anyone who can leave a comment can trigger it. Tightening the parser never finishes. It moves the hole. Five sound fixes produced five holes in the same place. Where a control is genuinely needed, take the tool away from the agent instead of trying to parse what it writes.
- **Match the control to what is actually at risk.** Single tenant, dev phase, no outside contributors, and the threat is a drifted agent holding the maintainer's credential. That credential also administers the ruleset, so it beats any in-repo gate by construction. A control that cannot stop its own attacker costs something and buys nothing.
- **Fail-closed is for security decisions, not for plumbing.** Pointed at an unreliable evaluator it creates outages. One unreadable policy file classified *every* PR as high risk, turning a single file-path bug into a repo-wide merge block.
- **Enforcement changes go through settings first.** Rulesets are editable through the API, atomically, with no PR. Flip the setting, then land the code that matches. Never ship a change whose own merge depends on the thing it is changing.
- **No check joins `required_status_checks` until one live PR has passed through it the happy way, watched.** That gate went required before a single clean PR had greened through its intended path, and that path turned out to be unable to fire at all.
- **Product PRs never wait behind gate PRs.** The gate series is its own lane. Queue product work behind it and one subsystem's outage becomes the whole run's.

## 7. One merge at a time, and cascade by hand

> **Queue repos (prismalens#403, merge queue enabled):** where
> `kit-meta.sh get <repo> merge_queue` returns true, which today is prismalens and
> sreforge, the cascade mechanics below no longer apply. The queue tests a speculative
> merge, so merges neither strand siblings nor need serialising, and `gh pr merge`
> enqueues. What still applies is the race: **the queue gates on checks and threads,
> not on whether a reviewer has spoken.** So on a queue repo, enqueue only after the
> PR's liveness comment shows posted review output. Otherwise report it ready and leave
> it (§10). A liveness comment reading *auto-paused* is not review evidence: the lane
> declined that head, so summon `@claude review` and get a posted review first. Classic
> repos such as mage-memory still follow everything below.

**Never arm auto-merge while reviewers cannot block a merge.** With no review-related check required, auto-merge fires the moment CI goes green, routinely before the reviewer finishes. Measured on prismalens#388 at `2bcdbcaf`: the `CI gate` ran 05:42:58 to 05:43:01 while the `review` job ran 05:40:58 to 05:43:42, so the merge condition was satisfiable **41 seconds before the reviewer was done**. The findings then land on an already merged PR, `required_review_thread_resolution` has nothing to block on, and review enforcement is zero.

For an unattended run this means: an organizer that cannot merge with the operator present does **not** arm auto-merge instead. It takes the PR to green, reports it ready, and leaves the merge (§10).

The way out is under consideration and not settled: `required_approving_review_count: 1` satisfied by a job that approves after the reviewer has run, with the **token held by that job and never by the reviewing agent**. The reviewing agent reads diff content an attacker can write, so otherwise a prompt injection becomes a self-approval.

Every merge puts every other open PR behind the base branch again, and auto-merge never updates a branch in that state.

- Merge one at a time, checking the gate after each.
- Cascade by hand: after each merge, update the next branch, wait for its required checks to go green on the new base, then merge.
- When PRs contend over one shared file such as a lockfile or a generated artifact, land the smallest delta first. Each landing forces the rest to regenerate.
- With no scheduled sweeper, a PR that merely falls behind triggers **nothing**. Its status sits stale forever. Nothing announces this, so go and look.
- Rebase the PRs you are deliberately parking at the **end** of the drain. Rebasing them early just puts them behind every merge that follows.

## 8. Check every delegate claim against live state

A returned report is a guess until confirmed. Before it changes a decision, check it against the thing itself: the head SHA, the check's description string, the job log, the file at that SHA. A diff claimed as one line gets read. Two lanes agreeing raises no confidence at all, because they can share one stale input, and did.

A PR body claiming what the PR does **not** do gets checked against the file list rather than taken on faith. One body said two scripts would be kept while its own diff deleted them, and it merged with the deletions on screen. Checking is cheap. A body that contradicts its diff is invisible afterwards.

## 9. Never bypass a ruleset or a gate

When a gate blocks the only fix available, **escalate. Do not override.** Waiting out a cooldown inside an eight hour window is cheap. A bypass cannot be undone.

First tell a gate that is **failing**, where retrying is right, from one that **cannot be satisfied**, where retrying burns the rest of the run for nothing. One required check demanded a reviewer artifact the reviewer only emits when it has findings, so a correct trivial change could never produce that evidence and the fix for the gate could not pass the gate. The tell: the same action gives the same empty result twice with no error. On the second identical empty result, stop and escalate. Do not try a third time.

What makes this bite: the PR that *repairs* the gate is the **worst** candidate in the repo for skipping review. Every catch an independent reviewer made on that track landed in exactly that territory, **including ones the adjudicating model had already approved.** A gate change reviewed only by the model that wrote it is the precise failure independent review exists to catch (§6).

- A **conditional** pre-authorisation ("this might need a bypass") is a reserve, not an instruction. Write down the exact condition that would spend it, and do not spend it just because things are slow.
- Never reach for a skip flag, an `--admin` merge, a `--no-verify` push, or a ruleset edit. If a lane already used one, record it and stop that lane. Do not quietly keep the result.
- Stuck on a real dilemma, ask the planner seat: a fresh agent on the strongest planning model, given the decision, the constraints and the options, not the whole run. Frame the question around the **subsystem**, not the hole in front of you (§6). If the last consult is over an hour old, start a new one instead of resuming it, because a stale consult reasons from premises the run has since disproved. Its ruling binds that decision, and what it explicitly deferred stays deferred.

## 10. Park anything that needs the operator to sign off

- Work that changes what the operator sees or owns goes **to green and stops**: interface shape, exported API, architecture naming, scope. Never merge it.
- PRs that have diverged, been superseded, or gone obsolete get a **comment** stating the state and stay open. Never close one. "Obsolete" is the operator's call, not yours. A PR earns the comment-and-leave treatment when its own body puts it outside the current scope, when it carries an open question only the operator can answer, or when its diff no longer applies to the current base for some reason other than a mechanical rebase. Age alone is not divergence.
- An honest gap beats an invented claim. Where the evidence for a parked item is incomplete, say so in the artifact.
- Every parked item goes in the plan file's decision list as a specific question with options, never as "needs review".

## 11. Short output: the operator is reading a terminal

Findings, decisions, evidence, SHAs, blockers. Do not restate the plan, do not narrate what you are about to do, do not re-summarise work already logged. Every dispatched agent gets the same instruction. **A tick with no dispatch is a valid tick**, one line with the reason.

Short is about length, not vocabulary. Write plain sentences a reader who was not watching can follow, and keep identifiers, commands and error text exact. Compressing the words is fine. Compressing the meaning is not.

Lead with what **landed**, and the SHAs of anything merged or pushed, before anything pending. One lane merged the first PR of an eight hour run, then reported only that it was waiting on a cooldown. The organizer found out about the merge by checking independently. Saying nothing about a finished step reads as "it did not happen" and costs a verification round.

A lane that refuses an unsourced order to spend a one-shot resource is behaving correctly, not disobediently (§1). Say so in the report rather than treating it as a failed dispatch.

## Wake-up checklist (each tick)

1. Read the plan file first. It holds the state, not your memory.
2. Confirm the cron is still armed (`CronList`). If the session restarted, it is gone (§0).
3. Confirm every lane is **alive** by listing agents. Never assume. Any lane saying "standing by" gets the §4 fix before anything else.
4. Check real state rather than reports: default branch SHA, each PR's head SHA, each gate's description string.
5. Re-check that the scarce resource is available (§2) before spending it.
6. Dispatch only work whose prerequisites are final. Starting a lane that depends on an in-flight template means writing it twice.
7. Append findings and decisions to the plan file. One or two lines to the terminal.

Hand back on a hard blocker or when all the work is genuinely done, not on a timer. Land whatever end-of-session deliverable the operator asked for, tear down the cron and any other watches (§4), and leave the plan file's decision list as the first thing they read. Each entry is a question, its options, and what it blocks.
