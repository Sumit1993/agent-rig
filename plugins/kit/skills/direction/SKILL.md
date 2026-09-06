---
name: direction
description: "Answer where the estate stands and what to work on next, across every repo it is configured for, without reading an issue list. Load when a session is asked what to do next, when picking up work cold, or when a repo's queue has to be ranked. Priority is a p0 label, placement is a numbered milestone, and the pick is one command."
---

# Direction

Run `direction.sh` first. Pass `owner/repo` when you are working in one repo, and the pick is the first line of that repo's block. With no argument it surveys the estate, repo blocks in goal order, and the pick is the first line overall. Never run an unfiltered `gh issue list`; that is the failure this replaces.

A goal is a milestone whose title starts with three digits and a space, `010 R1 - ...`. Lower number is earlier. A milestone without that prefix is a bucket and is never current. There are no due dates anywhere and nothing is ever overdue.

An issue with no milestone is not startable. It is triage debt and appears in section 5.

`p0` sorts an issue to the front of its own goal. It never crosses goals and never makes an unplaced issue startable. Section 1 is a diagnostic, not a pick: a line reading `NO MILESTONE` or `LATER GOAL` is a triage flag to report, not work to start.

Sequence inside one goal is carried by a `blocked` label plus a comment naming the blocker. Never a hand-written ordered list in an issue body. A candidate marked `body-says-blocked` has a blocker written in prose that no query can read: open it before starting, and if the blocker is real, give it the label.

The full ruling, with the evidence and the falsifiers, is `Sumit1993/claude-kit#100`.
