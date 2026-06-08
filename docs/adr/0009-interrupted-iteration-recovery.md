# Interrupted-iteration recovery: redo-from-scratch on an engagement branch

When an AFK iteration is killed mid-flight (credit exhaustion, crash) it lands
*between* the two clean exits — commit-on-success and `git stash -u`-on-failure —
leaving indeterminate state: the issue still `open`/`ready`, a dirty working tree,
and (in Model B / remote test source) WIP commits already pushed to the branch.
We recover by **redoing the issue from scratch** rather than resuming partial work,
because each iteration is already designed to be idempotent and partial state is not
trustworthy to continue from.

To make redo mechanical instead of guesswork, two things are fixed:

1. **Engagement branch.** A Model B engagement runs on a stable, milestone-derived
   branch `ralph/<milestone>`, created by a human before launch. It is the remote
   test oracle (`origin/<branch>`) and the only branch recovery force-pushes. `main`
   is never the engagement branch.
2. **Iteration baseline.** ralph records HEAD at the start of each iteration (before
   invoking the configured Agent CLI). Recovery resets the engagement branch to that SHA, so the reset
   target is recorded fact, not inferred from `git log`.

## Considered options

- **Resume partial work** — rejected: requires trusting indeterminate state and the
  agent reconstructing intent; fragile, and undermines per-iteration idempotency.
- **Branch per issue** — rejected: cleaner isolation but more branch churn and the
  recipe must resolve which branch is the test ref; per-milestone branch is enough.
- **Fully automated preflight self-heal** (auto-detect stale `running` + auto
  reset/force-push) — deferred: true unattended recovery, but auto force-push risks
  nuking legitimate WIP on misdetection. Force-push stays human-triggered for now.

## Consequences

- ralph must record the iteration baseline (e.g. `.ralph-logs/<scope>/baseline`)
  alongside the `running` PID file. The stale `running` file is the crash signal.
- Recovery is a **human-run runbook**, not code:
  1. Confirm the crash: `running` PID in `.ralph-logs/<scope>/` is no longer alive.
  2. Read the baseline SHA + issue number from the iteration record.
  3. Confirm the issue is still `open`/`ready` (it should be).
  4. `git reset --hard <baseline>` then `git clean -fdx`.
  5. `git push --force-with-lease origin ralph/<milestone>`.
  6. Re-run `ralph run <N> <milestone>` — the same issue re-picks and redoes clean.
- Until ralph records the baseline, step 2 is eyeballed from the tip after the last
  closed issue — the failure mode this ADR exists to remove.
