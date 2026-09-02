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
