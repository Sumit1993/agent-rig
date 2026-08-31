---
name: anti-stall
description: "Doctrine for waiting on long-running work without dozing: sentinel-first launches, evidence-keyed waits held in the background by a main session and in the foreground by a handler subagent, batch scripts over agent-per-step, and killing a run without reaping your own shell. Load BEFORE launching any delegation, build, campaign, CI run, or command expected to outlive one turn, whenever a wait has gone quiet longer than expected, and before any pgrep/pkill against a job you launched."
metadata:
  version: "1.2.0"
---

# Anti-stall: waiting on long work

Every observed stall has the same root cause: the wait keyed on **process liveness or a timer**, a Monitor asking "is it alive", a warmup countdown, "did setup exit". Every wait keyed on **durable evidence** worked: a sentinel line, an artifact file, a commit. That is the whole doctrine.

## 1. Sentinel-first
Every long command logs to a file and appends its own exit fact:

```bash
(<cmd> > "$LOG" 2>&1; echo "DONE rc=$?" >> "$LOG")
```

Without a sentinel the completion signal is transient and a missed wake loses it. With one, the fact is still in the log on the next check.

## 2. Wait = until-loop on evidence, foreground or background by who is waiting
Block on the durable fact, never on liveness or a timer:

```bash
for i in $(seq 1 N); do grep -q DONE "$LOG" && exit 0; sleep 15; done; echo WATCH_TIMEOUT
```

Size `N` as the deadline: `expected_minutes * 4 + 40`. The loop length **is** the timeout. `WATCH_TIMEOUT` in the log means stop waiting and go salvage.

**Where the loop runs depends on whether your context outlives it.**

- **Main session: background.** Start it right after launch. Its completion fires exactly
  one notification, and the session is still there to receive it. That is the wake signal.
- **Handler subagent: foreground.** Hold the wait with repeated bounded Bash calls instead.
  A subagent that arms a background loop and then ends its turn destroys the context the
  wake would have landed in. The run continues unwatched, and the parent gets a completion
  notice for a handler that did nothing. **A handler never ends a turn while its run is
  alive.** §5 is the cure for this after the fact; the rule here is the prevention.

**The Monitor tool is banned for this.** A Monitor gated on `pgrep`/timers can sleep through wake after wake without ever firing. Monitor is fine for genuinely open-ended watching (new PR comments, a file that may change), never for "did this finish".

## 3. Never wait on a condition the event itself prevents
Before arming any loop, ask whether the thing you are waiting to hear about could *stop*
the exit condition from ever being true. If it can, the loop is silent-forever: it spins to
timeout looking exactly like slow progress.

A loop that waits on the condition a review finding itself blocks is silent-forever:

```bash
until [ "$(gh pr view 495 --json mergeStateStatus --jq .mergeStateStatus)" = "CLEAN" ]; do sleep 30; done
```

An unresolved review thread pins `mergeStateStatus` at `BLOCKED`. So a posted finding, the
one event worth waking for, is the event that guarantees this loop never exits. Story: prismalens#495.

- **A PR wait keys on `reviewThreads` and comment IDs, never on merge state.** Any increase
  is the event. Merge state is an output of the thing you are waiting for, not a signal
  about it.
- `BLOCKED` is ambiguous. It means "CI still running" or "a reviewer left findings", and
  the two want opposite responses. Query `reviewThreads` to tell them apart. Never guess.
- The general form: the signal must be free to move when the event happens. If the event
  freezes it, pick another signal.

## 4. Check before waiting
**Any** wake means the expected notification, an unrelated one, or a user message. On all of them, check the sentinel and the expected artifacts **first**, then decide. A turn that ends "waiting" without a fresh check is the single most common stall.

## 5. Orchestrator watches evidence, not reports
Treat a handler subagent saying "waiting" as suspect. Never acknowledge two consecutive "waiting" reports without reading the log or worktree yourself. Resume it with "check evidence now, continue foreground" instead.

## 6. Deadline fallback
At expected duration + 10 min of silence, read the logs yourself and salvage. **Work often landed despite a silent handler.** Check artifacts before re-running anything, or you redo finished work.

## 7. Batch mechanical sequences, don't babysit them
If the remaining work is a known list of steps (N campaign runs, M migrations), write it as **one unattended script** with a per-step sentinel and a final marker, failures logged-and-continued:

```bash
for id in "${STEPS[@]}"; do
  <run "$id"> >> "$LOG" 2>&1; echo "STEPDONE $id rc=$?" >> "$LOG"
done
echo BATCH_COMPLETE >> "$LOG"
```

Wake once, at the end. Agent-per-step is where dozing lives; a script cannot doze.

## Killing safely
Any `pgrep -f` / `pkill -f` whose pattern appears in your own shell's command line kills
**your own shell** (exit 144).

**Kill by PID.** Capture it at launch (`PID=$!`) and keep it. Everything below is for when
the PID is genuinely lost.

**The bracket trick is necessary and not sufficient.** `"issue39[-]rca"` hides the pattern
from its own literal, and that is all it does. Under the Claude Code Bash tool every call
runs as `bash -c 'eval <your whole command>'`, so your shell's command line holds the
entire command. If the unbracketed string appears anywhere else in it, an `echo`, a
`printf`, a filename you just created, the bracket protects nothing and the kill reaps your
shell. This is easy to hit while testing a kill pattern, which is exactly when you are
least expecting it.

Two things that actually hold:

- **Generate the marker at runtime.** `SLUG="run-$(date +%s)"` cannot appear in any
  ancestor's command line, because it did not exist when they were created. Self-unmatchable
  by construction rather than by escaping.
- **Never build the pattern in the same Bash call that mentions the string.** Put the kill
  in its own call.

```bash
kill -9 "$PID"                      # preferred
kill -9 $(pgrep -f "$SLUG")         # fallback, marker generated this run
```

**A shared binary's processes are machine-global.** `pkill -x <name>` reaches every session
on the host, not just yours, and the runs you did not mean to touch die as an empty
non-zero exit that reads as an internal failure wherever they were being watched. If you
cannot resolve a PID you can prove is yours, by a `$!` you captured or a
`readlink /proc/<pid>/cwd` you recognise, kill nothing and say so.

**Match a pattern that is really on the target's argv.** A shell expands `$(cat file)`
before exec, so a prompt file's *name* never reaches the process it launched; it stays on
the launching shell instead. Killing on it reaps the wrapper and leaves the real job
running. Verify with `pgrep -a <pattern>` and confirm the match is the process you mean,
not merely that exactly one thing matched. `agy-delegate` carries the worked example.

Self-test at arm time: run `pgrep -a "<pattern>"` once and read what came back. It must
match the process you intend to kill. "Exactly one PID matched" is not the test, because a
wrapper alone satisfies it while the real job goes untouched.
