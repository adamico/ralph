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
