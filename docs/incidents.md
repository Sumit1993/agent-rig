# Incidents behind the rules

One paragraph per incident. A skill cites the slug; the story lives here so it stops loading on every turn. Add a paragraph when a rule is born from a failure, and keep the slug stable.

## stale-working-tree-seeds-canon-repo

An agy prompt told the lane to copy workflow files from another repo. The lane read the local checkout's working tree, which had been fetched but not pulled, so the files were pre-fix. The stale copies went into the canon repo and two consumer repos. A canary PR caught it. A fetch updates refs, not files, so reference content must come from `gh api` or `git show origin/main:<path>`.

## claude-kit-kill-destroys-prismalens-run

A test suite in claude-kit ran a name-wide kill against agy. It reaped a prismalens run mid-implementation on a release blocker. In that session it surfaced as rc=137 with an empty log, which looks like silent quota death, and the handler there spent its retry budget relaunching into a lane it believed was broken. agy processes carry no session or repo identity, so a kill by name reaches every session on the machine.

## gh-workflows-69-unwatched-pr

An agy lane opened gh-workflows PR #69. The review lane reviewed it automatically and nobody was watching, so the findings sat unread. A handler cannot hold a Monitor past its turn, so the fix is for the handler to put the PR URL in its report and for the main session to arm `pr-watch`.

## gh-workflows-d1-cron-tick

On a gh-workflows unattended run the evidence was a Cloudflare D1 `usage_records` row, reachable only through the Cloudflare MCP server. The box had no `CLOUDFLARE_API_TOKEN`, it lived as a repo secret, so no shell loop and no Monitor could poll it. The only working poll was a cron tick firing back into the session so the model made the MCP call itself.

## prismalens-495-blocked-forever

On prismalens PR #495 a wait loop polled `mergeStateStatus` until it read `CLEAN`. An unresolved review thread pins that field at `BLOCKED`, so the one event worth waking for, a posted finding, was the event that kept the loop from ever exiting. It spun to timeout looking like slow progress.

## merge-queue-scope-narrowing

prismalens #403 rolled out the merge queue. The queue tests a speculative merge onto main before landing, so cascade shepherding (update-branch, BEHIND babysitting, `merge-cascade.sh`) stopped being the watcher's job, and the liveness comment now says on the PR itself whether a reviewer posted. `pr-watch` shrank to one PR, one session, one round.

## auto-merge-outruns-reviewer

On mage-memory PR #133 auto-merge fired between a review landing and its fix commit. The thread gate only blocks once a thread exists, and a reviewer that has not posted yet has no threads, so the PR merged before the finding was addressed. Order the round as review posted, fix, resolve, merge.

## watcher-outlived-repurposed-pr

A watcher left running past its lane kept acting on a PR that had since been repurposed, and spent a scarce CodeRabbit review on it unprompted. A watcher dies with its task, not with the session.

## author-association-misdiagnosis

On prismalens/gh-workflows #20 a summon refusal was diagnosed by reading `author_association`. That field is repo-scoped and payload-dependent, so the webhook value and the REST value disagreed for the same comment. The gate checks live write access through the collaborators API, so the field is never the value the gate saw.

## auto-pause-wait-forever

On prismalens/gh-workflows #28 a watcher waited for the next push to bring a review. The lane had auto-paused after five automatic rounds, and a paused PR is not reviewed on push, so the wait had no end. Only a summon resumes it, and only when that round posts output.

## dedup-silent-empty-review

On prismalens/prismalens #410 a review round finished green having published nothing. Dedup had suppressed every finding as already covered. `@claude full review` disables dedup for that run and is the fix.

## cancelled-vs-skipped-confusion

A run concluded `cancelled` with zero jobs. It had been evicted from its concurrency group before any `if:` was evaluated, so it said nothing about admission, but it was read as a refusal and a full session went into diagnosing an admission gate that had never run. `skipped` is a refusal; `cancelled` with zero jobs is an eviction.

## verify-round-reply-eviction

Every review round ended by posting a top-level verdict comment. That fired `issue_comment` into the PR's concurrency group and took the single pending seat from any queued in-thread reply, so a reply posted while a round ran was dropped, every time. Bot-authored comments now route to a per-run throwaway group.

## prismalens-415-retires-automatic-admission

`review-admit.yml` applied the `coderabbit_review` label on a path match against `.github/high-risk-paths.txt`, and a `review-evidence` gate held such PRs red until `coderabbitai[bot]` evidence existed. prismalens #415 retired both. Neither file is on main, and admission became a hand-applied label.

## traffic-outruns-counter-measurement

Measured over 180 prismalens merges: 7.5 PRs a day, worst hour 8 opens, and at one review per hour 61% of PRs arrived with the counter already empty. Automatic review spent the budget where PRs happened to fall, not where a second opinion was worth having.

## claude-kit-28-rate-limit-wording-gap

claude-kit #28 recorded three wordings CodeRabbit has used for its cooldown notice. The watcher's pattern matched only the first, so every rate limit silently armed the 3600-second fallback instead of the notice's figure.

## flat-60-minute-wait-error

Waiting a flat 60 minutes from the refusal has the right magnitude and the wrong anchor. The window is anchored to the last accepted review, so the flat wait landed about 21 minutes late, and because nothing re-read the notice the error stayed invisible.

## session-misused-unattributed-cooldown-figures

A session built arithmetic on "roughly 40 minutes", "37 rejected", "45 or more succeeds", figures nobody had dated or attributed to a plan, and reached a confident wrong conclusion. They disagree with the 3600-second fallback and with longer waits observed since.

## settled-body-classification-trap

CodeRabbit edits its cooldown reply in place while composing it. A poll that matched `rate limited` once and stopped acted on a draft; the number it needed was in the settled version.
