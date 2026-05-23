# ADR-0001: Issue priority rules for ralph loop

## Status

Accepted.

## Context

ralph drains a queue of issues unattended. Each iteration must pick exactly
one issue deterministically, with no human in the loop. The algorithm has to
work over a flat directory of `.md` files (filesystem backend) and the same
shape lifted into GitHub Issues (github backend).

We need a rule that:

- is stable across runs (same state → same pick),
- expresses dependencies without a build system,
- degrades to an explicit halt when nothing is pickable,
- is cheap to evaluate in bash.

## Decision

Each issue file carries a header block terminated by `---`:

```
Status: ready|done|blocked
Blocked-by: 02-scaffold, 04-tests
Blocked-reason: <free text, set when Status: blocked>
---
<body>
```

`Blocked-by:` is optional and comma-separated. Entries reference other issue
filenames without the `.md` extension.

The pick algorithm:

1. Enumerate `issues/*.md` in lexical order (filename sort).
2. Skip any with `Status: done`.
3. Of the remainder, the candidate is the **lowest filename** where:
   - `Status: ready`, and
   - every entry in `Blocked-by:` resolves to an issue file with `Status: done`.
4. If a candidate exists, that is the pick.
5. If no candidate exists but unfinished (non-done) issues remain, emit
   `<promise>BLOCKED</promise>` and stop. A human must edit a header.
6. If every issue is `Status: done`, clear `.scratch/ACTIVE` (write empty
   file) and emit `<promise>COMPLETE</promise>`.

On a successful iteration the agent sets the picked issue to `Status: done`,
appends a paragraph to `progress.txt`, and commits the issue file + code +
progress together.

On failure the agent runs `git stash -u`, sets the issue to
`Status: blocked` with a `Blocked-reason:` line, and commits **only** the
header change with a `[blocked]` commit-message prefix. Stashed work is
discarded by the human on review.

## Consequences

- Filename prefix (`02-`, `03-`, …) is the priority knob. Reordering work
  means renaming files.
- A cycle in `Blocked-by:` deadlocks into `BLOCKED`. That is the desired
  failure mode — a human breaks the cycle.
- The state machine is the file headers. No separate database, no lockfile,
  no daemon. `git log` is the audit trail.
- `Blocked-by:` referencing a non-existent file is treated as not-done, so
  typos surface as `BLOCKED` rather than silent picks.
