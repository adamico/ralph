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

**Iteration** — one invocation of `iterate_once`: pick an issue, invoke Claude,
handle the result (done / blocked / complete / error).

**Sandbox** — the isolated container an AFK iteration runs inside, wrapping the
entire Claude invocation (`CLAUDE_CMD="sbx run <name> --"`). One run = one
sandbox = one engine. Named `<repo>-<console>` for engine ports.

**Recipe** — a bundled, reusable setup for a given engine (sandbox build +
test harness + `.ralph.conf` shape) that `ralph-init` instantiates so a new
port does not re-derive it. Classified by **tier**.

**Tier** — how mature a recipe is: *mature-external* (imported from a proven
repo, e.g. dragonruby from `adamico/locomotion`), *standard* (e.g. littlejs
node/vitest), *host-fallback* (no container yet, e.g. pico8/picotron).

**Test source** — which copy of the code a recipe's test harness exercises,
selected by `<ENGINE>_TEST_SOURCE`: `local` (the host workspace in place, picks
up uncommitted WIP) or `remote` (a fresh `git clone` of the GitHub origin inside
the sandbox, isolating linux build deps from the bind-mounted host). `remote`
sees **pushed commits only** — the agent must commit and push before tests
reflect its work. See ADR-0008 (push timing / test oracle) and ADR-0022 in
`adamico/locomotion`.
