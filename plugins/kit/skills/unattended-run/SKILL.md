---
name: unattended-run
description: "Rules for holding a long unattended run: arm the wake-up first, keep the organizer out of the files, catch stalls, treat a green check as nothing, verify every delegate claim, park what needs a human. Load BEFORE any session where the operator is away and the work will outlast their attention: an overnight run, a multi-hour delegation, a cron-driven organizer's first wake-up. Also load whenever a lane reports \"standing by\"."
metadata:
  version: "2.0.0"
---

# Unattended run: holding a long autonomous session

One seat holds the goal across every wake-up. Every other seat is disposable.

Each rule below comes from a failure that already cost hours of a real unattended window, so each is written as the mechanism rather than the ban. Writing a rule down does not stop it being broken (§3).

Assumed here and not repeated: **`anti-stall`** for how a wait is built, **`agy-delegate`** for driving the cheap executor, **`pr-watch`** for one PR's lifecycle.

## 0. The first tick: arm the wake-up, then write the plan file

Nothing is dispatched until both exist.

### Arm the wake-up

With no scheduled wake-up the run is one turn long.

1. `CronCreate` is a deferred tool. Fetch it first:
   `ToolSearch("select:CronCreate,CronList,CronDelete")`. Nothing prompts you to, which is
   why this gets skipped.
2. **30 minutes, off the :00 and :30 marks where every scheduled job lands:**
   `7,37 * * * *`. Longer when the thing you are waiting on moves slower.
3. The prompt fires into **this** session, so the context is still here. Ask for current
   state: "tick: read the plan file, check lane and PR state, then dispatch or report."
4. `CronList` after, to confirm. A cron that failed to arm looks like a quiet run.
5. Record the job ID in the plan file beside the condition that ends it (§3).

Three facts change how the run is planned:

- **Jobs live in this session's memory only.** End the session and the cron goes with it,
  leaving a plan file that still reads healthy.
- **Jobs fire only while the REPL is idle.** A long foreground wait (`anti-stall` §2) blocks
  the tick. Keep those shorter than one interval.
- **Recurring jobs expire after 7 days.**

`ScheduleWakeup` paces `/loop` from inside a session and is not this. Use `CronCreate`.

### Write the plan file

`~/ai-context/<repo>-<task>-plan.md` is the source of truth. Scrollback usually survives a
wake-up, since the tick fires into this session. It does not survive compaction, a crash, or
the operator resuming in a new session. The plan file survives all three. It holds the
standing rules, the lane table, the decisions waiting on the operator, verified environment
facts, and a running log. Detail goes here, not the terminal (§11).

If it does not exist yet, building it is the rest of the first tick. Read the queue without
touching anything and group it into waves by what blocks what. Probe the environment rather
than assuming it: which stacks are up, which worktrees exist, which repo owns which name.
Write down the standing rules, including the ones the operator only said out loud, plus what
is frozen and what must never be merged.

**Respect the window.** Never start a lane that cannot finish *and* be verified in the time
left. Near the end, take work only to a state that is safe to leave: pushed, commented, or
parked. Never mid-merge or mid-rebase.

## 1. The organizer never edits repo files

Dispatch and judge. Editing a file means the seat holding the whole goal spent its turn on work a cheap lane could have done, and stopped watching every other lane while it did. The organizer produces dispatches, verdicts on returned claims, plan file updates, and merges. Nothing else.

Lanes work in worktrees, never in the main checkout. `AGENTS.md` sets which mechanism, and a Claude subagent lane and an agy lane do not get the same one. The main checkout and its stack belong to the organizer. A lane that helpfully "restores" its branch takes the run down with it. The organizer creates or reuses the worktree and hands the lane an absolute path, with instructions to stop and report if it is missing.

**Every dispatch prompt says, in as many words:**

- The absolute worktree path.
- The exact verify commands, and that the lane runs them itself.
- The report format: findings, evidence, SHAs, blockers, no prose.
- The stop conditions. "Abort and report rather than improvise" on any conflict, any frozen
  path, any gate still red after N minutes.
- What the lane may **not** do: merge, close, bypass, edit a frozen path.
- The stall rule (§3).

Never override a lane's brief with reasoning you invented on the spot. One organizer ordered a lane to spend the run's last unit of a scarce counter on an action its own brief had already called a guaranteed waste. The claim behind the order sounded right and had no source. The lane refused, correctly. If you contradict a brief, cite what supersedes it. With no source, the brief wins.

**Workflows and subagents are free to use. Cost is the only limit.** Do not ration agents
to save money and do not do work by hand to avoid spawning one. That trades the expensive
seat's attention for the cheap resource.

## 2. Delegate, then verify

Send bulk reading, log triage, rebases, evidence gathering and repetitive per-PR work to the cheap executor. **Never let its claims reach an artifact unchecked.** One drafting pass on PR bodies invented a UI button label and credited a screenshot to the wrong route. Both read as plausible, neither was visible in the draft, and checking the component source at the head SHA caught both. Cheap models gather and draft. Verification belongs to the organizer or a Claude handler, always against source at the exact SHA.

Judgment work skips the cheap lane entirely: security and crypto, anything users see, product semantics.

## 3. The stall rule: a wait has to hold the turn

**A lane that returns saying "standing by", "waiting for" or "will be notified" has stalled. It is not waiting.**

Here is why. A completion notification fires only when an agent has **no live background children**. The moment an agent launches something in the background and hands control back, that notification can never arrive. Returning guaranteed that nothing is watching. This keeps happening in lanes that were handed the rule, so treat it as a trap built into the tooling rather than a bad agent.

- A wait is real **only while the agent is still running inside its own turn**: a foreground `until` loop keyed on durable evidence, with the loop length as the deadline (`anti-stall` §2).
- A background launch followed by handing control back is a stall, every time.

**Fix it immediately and skip the acknowledgement.** `SendMessage` to that lane: "go read <the concrete artifact: log path, PR check, SHA>
now. Then wait in the foreground with a deadline. Do not return until the evidence
resolves or the deadline expires." Never accept two "waiting" reports in a row. Read the artifact yourself instead.

Put this rule in every dispatch prompt. Assume the lane walks into it otherwise.

**Some evidence has no shell poll at all.** If the only way to read it is an MCP tool
call, no Monitor and no background loop can watch it; a cron tick into this session is the
watch, and its latency is the tick interval. Record it as a tick, never as a monitor, or
the operator reads a 30 minute blind spot as a live poll. `anti-stall` §2 has the rules.

**The reverse failure: a watch that outlives its job.** A monitor, a poller, a cron tick. Anything armed to watch one piece of work gets torn down the moment that work ends, whether it merged, closed, moved, or was abandoned. One left running kept acting on a PR that had since been repurposed into something else, and spent a scarce shared counter on it unprompted. Arming something durable creates a teardown obligation in the same breath. Record it in the plan file's lane table beside the thing it watches, and disarm it as part of closing the lane.

## 4. A green job proves nothing. Only a posted artifact does

A workflow can report `success` having posted nothing at all, and does. One reviewing lane reported success while posting no review for two weeks. Every status-only read of it said the PR had been reviewed.

- Read the job that **produces** the artifact, not the wrapper check. A green review step means the lane ran. Only the thing it was supposed to post counts.
- A green gate whose description names a **retired producer** is a leftover, not a pass. It flips red the moment anything re-evaluates it, and a status-only read cannot see that coming.
- Two separate triage lanes read exactly that stale green as real and called the PR clean and ready to merge. Hence §5.

## 5. Check every delegate claim against live state

A returned report is a guess until confirmed. Before it changes a decision, check it against the thing itself: the head SHA, the check's description string, the job log, the file at that SHA. A diff claimed as one line gets read. Two lanes agreeing raises no confidence at all, because they can share one stale input, and did.

A PR body claiming what the PR does **not** do gets checked against the file list rather than taken on faith. One body said two scripts would be kept while its own diff deleted them, and it merged with the deletions on screen. Checking is cheap. A body that contradicts its diff is invisible afterwards.

## 6. Ask the planner seat when the call is a judgment

Some decisions are not yours to improvise: architecture, security and crypto, product
semantics, and any dilemma where two rules you were given point opposite ways.

Spawn `fable-planner`, a fresh agent on the strongest planning model. Give it the decision,
the constraints and the options. Not the whole run.

- Frame the consult around the subsystem, not the hole in front of you (§7).
- One consult per decision. If the last is over an hour old, start a new one rather than
  resuming it, because a stale consult reasons from premises the run has since disproved.
- Its ruling binds that decision, and what it explicitly deferred stays deferred.
- A ruling you disagree with is still the ruling. Record the disagreement in the plan file
  and park it for the operator (§10).

## 7. Gates and rulesets: flip the setting, do not build the machine

This is about CI gates, branch rulesets and review-enforcement workflows. Changing one is
not like changing product code: a broken gate blocks every PR in the repo, including the PR
that fixes it. Six PRs in one series each had to pass the check they were repairing.

- **Ask whether the gate should exist at all before asking how to fix it.** Decide per
  subsystem, not per hole. Four rulings on one gate were each locally right and together
  wrong, because nobody asked the first question until all four had landed.
- **Prefer a setting to a workflow.** Rulesets are editable through the API, atomically,
  with no PR. One hand-built gate turned out to duplicate
  `required_review_thread_resolution`, already switched on in the same ruleset.
- **Never write a check that parses a vendor's text**: comment bodies, review states,
  marker strings. None is a documented contract and anyone who can comment can trigger it.
  Tightening the parser moves the hole rather than closing it. If you need a control, take
  the tool away from the agent instead.
- **Never ship a change whose own merge depends on the thing it is changing.** Flip the
  setting first, then land the code. Nothing joins `required_status_checks` until one live
  PR has passed through it, watched. Product PRs never queue behind gate PRs.
- **Fail-closed is for security decisions, not plumbing.** One unreadable policy file
  classified every PR as high risk and blocked the whole repo.

## 8. Merging: take it to green and leave it

Mechanics live in `pr-watch` Phase 3, including which repos use the queue. What is specific
to running unattended:

**Never arm auto-merge.** Reviewers cannot block a merge, so it fires the moment CI goes
green, routinely before the reviewer has finished. Findings then land on an already merged
PR and `required_review_thread_resolution` has nothing left to block on. Story: prismalens#388.

**So an organizer that cannot merge with the operator present does not merge at all.** Take
the PR to green, report it ready, leave it (§10).

If the operator has granted merges on a classic repo: one at a time, checking the gate after
each. Every merge puts the other open PRs behind the base, and auto-merge never updates a
branch in that state, so nothing fires and nothing tells you. Go and look. Rebase the PRs
you are parking at the end of the drain, not the start.

## 9. Never bypass a ruleset or a gate

When a gate blocks the only fix available, **escalate. Do not override.** Waiting out a cooldown inside an eight hour window is cheap. A bypass cannot be undone.

First tell a gate that is **failing**, where retrying is right, from one that **cannot be satisfied**, where retrying burns the rest of the run for nothing. One required check demanded a reviewer artifact the reviewer only emits when it has findings. A correct trivial change could never produce that evidence, so the fix for the gate could not pass the gate. The tell: the same action gives the same empty result twice with no error. On the second identical empty result, stop and escalate. Do not try a third time.

What makes this bite: the PR that *repairs* the gate is the **worst** candidate in the repo for skipping review. Every catch an independent reviewer made on that track landed in exactly that territory, **including ones the adjudicating model had already approved.** A gate change reviewed only by the model that wrote it is the failure independent review exists to catch (§7).

- A **conditional** pre-authorisation ("this might need a bypass") is a reserve, not an instruction. Write down the exact condition that would spend it, and do not spend it just because things are slow.
- Never reach for a skip flag, an `--admin` merge, a `--no-verify` push, or a ruleset edit. If a lane already used one, record it and stop that lane. Do not quietly keep the result.
- A real dilemma goes to the planner seat, not to your own judgement (§6).

## 10. Park anything that needs the operator to sign off

- Work that changes what the operator sees or owns goes **to green and stops**: interface shape, exported API, architecture naming, scope. Never merge it.
- PRs that have diverged, been superseded, or gone obsolete get a **comment** stating the state and stay open. Never close one. "Obsolete" is the operator's call, not yours. A PR earns the comment-and-leave treatment on three grounds: its own body puts it outside
  the current scope, it carries an open question only the operator can answer, or its diff
  no longer applies to the base for some reason other than a mechanical rebase. Age alone is
  not divergence.
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
3. Confirm every lane is **alive** by listing agents. Never assume. Any lane saying "standing by" gets the §3 fix before anything else.
4. Check real state rather than reports: default branch SHA, each PR's head SHA, each gate's description string.
5. Dispatch only work whose prerequisites are final. Starting a lane that depends on an in-flight template means writing it twice.
6. Append findings and decisions to the plan file. One or two lines to the terminal.

Hand back on a hard blocker or when all the work is genuinely done, not on a timer. Land whatever end-of-session deliverable the operator asked for, tear down the cron and any other watches (§3), and leave the plan file's decision list as the first thing they read. Each entry is a question, its options, and what it blocks.
