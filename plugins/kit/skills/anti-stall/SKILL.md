---
name: anti-stall
description: "Doctrine for waiting on long-running work without dozing: sentinel-first launches, evidence-keyed waits held in the background by a main session and in the foreground by a handler subagent, batch scripts over agent-per-step, and killing a run without reaping your own shell. Load BEFORE launching any delegation, build, campaign, CI run, or command expected to outlive one turn, whenever a wait has gone quiet longer than expected, and before any pgrep/pkill against a job you launched."
metadata:
  version: "2.0.0"
---

# Anti-stall: waiting on long work

Every stall had the same cause: the wait keyed on process liveness or a timer. Every wait keyed on durable evidence worked: a sentinel line, an artifact file, a commit. Stories are in `docs/incidents.md`.

## 1. Sentinel first

Every long command logs to a file and appends its own exit fact:

```bash
(<cmd> > "$LOG" 2>&1; echo "DONE rc=$?" >> "$LOG")
```

Without it the completion signal is transient and a missed wake loses it.

## 2. Wait on evidence, foreground or background by who waits

```bash
for i in $(seq 1 N); do grep -q DONE "$LOG" && exit 0; sleep 15; done; echo WATCH_TIMEOUT
```

- `N` is `expected_minutes * 4 + 40`. The loop length is the timeout. `WATCH_TIMEOUT` in the log means stop waiting and salvage.
- Main session: background, started right after launch. Its completion fires one notification and the session is there to receive it.
- Handler subagent: foreground, repeated bounded Bash calls. A handler never ends a turn while its run is alive. A backgrounded loop plus an ended turn destroys the context the wake would land in, the run goes unwatched, and the parent gets a completion notice for a handler that did nothing.
- The Monitor tool is banned for "did this finish". Gated on `pgrep` or timers it sleeps through wake after wake. Monitor is for open-ended watching only: new PR comments, a file that may change.

### Evidence only an MCP tool can read

When no shell can reach the evidence, the one poll left is a cron tick firing back into the session so the model calls the tool itself (`unattended-run` §0).

- Do not call it a monitor. In the plan file it is "cron tick every N min, calls `<tool>`". Latency is the full interval and nothing fires between ticks.
- Set N from how fast the watched thing moves, and record the number beside the watch.
- Look for a shell path once first. A missing credential is the usual reason there is none, and a secret in CI can sometimes be granted to the box.
- A tick carries the same teardown duty as any watch (`unattended-run` §3): kill the cron when the thing resolves.

Story: `gh-workflows-d1-cron-tick`.

## 3. Never wait on a condition the event prevents

Before arming a loop, ask whether the event you wait for could stop the exit condition from ever being true. If so the loop is silent forever and looks like slow progress.

```bash
until [ "$(gh pr view 495 --json mergeStateStatus --jq .mergeStateStatus)" = "CLEAN" ]; do sleep 30; done
```

An unresolved review thread pins `mergeStateStatus` at `BLOCKED`, so the posted finding is the event that guarantees this never exits (`prismalens-495-blocked-forever`).

- A PR wait keys on `reviewThreads` and comment IDs, never on merge state. Any increase is the event.
- `BLOCKED` means "CI running" or "reviewer left findings", and the two want opposite responses. Query `reviewThreads`. Never guess.
- General form: the signal must be free to move when the event happens. If the event freezes it, pick another signal.

## 4. Check before waiting

Any wake, expected or not, including a user message: check the sentinel and expected artifacts first, then decide. A turn that ends "waiting" without a fresh check is the most common stall.

## 5. Watch evidence, not reports

A handler saying "waiting" is suspect. Never accept two consecutive "waiting" reports without reading the log or worktree yourself. Resume it with "check evidence now, continue foreground".

## 6. Deadline fallback

At expected duration plus 10 minutes of silence, read the logs yourself and salvage. Work often landed despite a silent handler. Check artifacts before re-running anything.

## 7. Batch mechanical sequences

A known list of steps becomes one unattended script with a per-step sentinel and a final marker, failures logged and continued:

```bash
for id in "${STEPS[@]}"; do
  <run "$id"> >> "$LOG" 2>&1; echo "STEPDONE $id rc=$?" >> "$LOG"
done
echo BATCH_COMPLETE >> "$LOG"
```

Wake once, at the end. Agent-per-step is where dozing lives.

## Killing safely

Any `pgrep -f` or `pkill -f` whose pattern appears in your own shell's command line kills your own shell, exit 144.

- Kill by PID. Capture `PID=$!` at launch and keep it. The rest is for a lost PID.
- The bracket trick (`"issue39[-]rca"`) is necessary and not sufficient. Every Bash tool call runs as `bash -c 'eval <your whole command>'`, so an `echo`, a `printf` or a filename in the same call holding the unbracketed string defeats it.
- Generate the marker at runtime: `SLUG="run-$(date +%s)"` cannot be in any ancestor's command line.
- Never build the pattern in the same Bash call that mentions the string. The kill gets its own call.
- `kill -9 "$PID"` preferred. `kill -9 $(pgrep -f "$SLUG")` as fallback, marker generated this run.
- A shared binary's processes are machine-global. `pkill -x <name>` reaches every session on the host, and the runs you did not mean to touch die as an empty non-zero exit that reads as an internal failure where they were watched.
- Prove a PID is yours, by a captured `$!` or a `readlink /proc/<pid>/cwd` you recognise, or kill nothing and say so.
- Match a pattern that is on the target's argv. A shell expands `$(cat file)` before exec, so a prompt file's name reaches only the launching shell, and killing on it reaps the wrapper. `agy-delegate` has the worked example.
- Self-test at arm time: `pgrep -a "<pattern>"` once, and read what came back. It must be the process you mean. "Exactly one PID matched" is not the test; a wrapper alone satisfies it.
