# ralph — Domain Glossary

## Terms

**PRD** — a bounded set of issues ralph drains in one engagement. In the fs
backend, a PRD is a directory under `.scratch/<name>/` containing `issues/*.md`.
In the GitHub backend, a PRD is a GitHub milestone. Not a planning document — the
name is shorthand for "the active queue."

**Milestone** (GitHub backend) — the GitHub milestone that scopes which issues
ralph considers. Passed as a positional argument (`ralph once <milestone>`), not
config. One milestone = one PRD. Closed issues = done work; open issues = pending
work.

**Issue** — a single unit of work. In the fs backend, a `.md` file with a
`Status:` / `Blocked-by:` header. In the GitHub backend, a GitHub issue inside
the active milestone with labels and a `Blocked-by:` body line.

**Pick algorithm** — selects the next issue to work on: lowest identifier (filename
or issue number) whose status is ready and all `Blocked-by` dependencies are done.
See ADR-0001.

**Iteration** — one cycle of ralph work: pick an issue, invoke an Agent CLI,
handle the result (done / blocked / complete / error).

**Agent CLI** — the command-line coding agent ralph invokes for an iteration.
Claude Code, Codex, Pi, and Antigravity are supported implementations of this role; domain
language should not treat any one implementation as synonymous with ralph itself.

**Sandbox** — the isolated container an AFK iteration runs inside, wrapping the
entire Agent CLI invocation. One run = one sandbox = one engine. Named
`<repo>-<console>` for engine ports.

**Recipe** — a bundled, reusable setup for a given engine (sandbox build +
test harness + `.ralph.conf` shape) that `ralph-init` instantiates so a new
port does not re-derive it. Classified by **tier**.

**Tier** — how mature a recipe is: *mature-external* (imported from a proven
repo, e.g. dragonruby from `adamico/locomotion`), *standard* (e.g. littlejs
node/vitest), *host-fallback* (no container yet, e.g. pico8/picotron).

**Model Class** — the cost/capability class ralph uses to select a default
Agent CLI model for unattended loops. Initially only `low` is defined; explicit
`MODEL` overrides the class default.
_Avoid_: Model tier, because **Tier** already means recipe maturity.

**Test source** — which copy of the code a recipe's test harness exercises,
selected by `<ENGINE>_TEST_SOURCE`: `local` (the host workspace in place, picks
up uncommitted WIP) or `remote` (a fresh `git clone` of the GitHub origin inside
the sandbox, isolating linux build deps from the bind-mounted host). `remote`
sees **pushed commits only** — the agent must commit and push before tests
reflect its work. See ADR-0008 (push timing / test oracle) and ADR-0022 in
`adamico/locomotion`.

**Engagement branch** — the stable branch a Model B engagement runs on, named
`ralph/<milestone>`. In remote test source it is the test oracle (`origin/<branch>`),
so the agent commits and pushes onto it for the whole engagement. Created by a
human before launch; never `main`. Force-pushed **only** during recovery. See
ADR-0009.

**Iteration baseline** — the HEAD commit captured at the start of an iteration,
before Claude is invoked. The reset target when redoing an interrupted iteration:
it marks the tip after the last successfully-closed issue (or the branch point for
the first issue). Recorded by ralph per iteration.

**Interrupted iteration** — an iteration killed mid-flight (credit exhaustion,
crash) between commit-on-success and stash-on-failure. Leaves indeterminate state:
the issue still `open`/`ready`, a dirty working tree, and — in Model B — WIP commits
already pushed to the engagement branch. Recovered by **redo-from-scratch**: reset
to the [[iteration-baseline]], clean, force-push the engagement branch, then re-run
(ralph re-picks the same issue). Not a resume. See ADR-0009.
