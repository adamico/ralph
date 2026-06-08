# ralph

Ralph Wiggum loop for AFK Agent CLI runs. `ralph` repeatedly invokes
one configured command-line coding agent with a priority-ordered queue of
issues until the queue drains, gets stuck, or you hit Ctrl-C.

Two backends ship in one script:

- **fs** (default) — issues are `.md` files under `.scratch/<active>/issues/`
  with a `Status:` / `Blocked-by:` header.
- **github** — issues live in a GitHub milestone; labels drive readiness.

See `docs/ADR-0001-priority-rules.md` for the pick algorithm and
commit/halt protocol.

## Install

```bash
git clone https://github.com/adamico/ralph.git
cd ralph
./install.sh                  # → ~/.local/bin/ralph
PREFIX=/usr/local ./install.sh  # → /usr/local/bin/ralph
```

Requires: bash, git. GitHub backend additionally needs `gh` and `jq`.

## Quickstart — fs backend

```bash
# In your project root:
cp <ralph-repo>/docs/examples/.ralph.conf .ralph.conf
mkdir -p .scratch/my-prd/issues
echo my-prd > .scratch/ACTIVE

# Drop issue files: .scratch/my-prd/issues/01-foo.md, etc.
# Header schema:
#   Status: ready            (ready|done|blocked)
#   Blocked-by: 02-bar, 03-baz
#   ---
#   <free-form spec>

ralph run 10
```

## Quickstart — github backend

```bash
# .ralph.conf
BACKEND=github
AGENT_CLI=claude            # claude | codex | pi
AGENT_CMD="sbx run my-project -- claude"
AGENT_ARGS=""              # optional adapter args
MODEL_CLASS=low             # cost/capability class
# MODEL=sonnet              # optional explicit model override
# GH_REPO="owner/name"      # optional; gh auto-detects from remote

ralph run 10 v0.1
```

The milestone argument (`v0.1` above) is the active work queue — the
GitHub equivalent of a `.scratch/<prd>/` directory in the fs backend.
Pass it each invocation to tell ralph which milestone to drain.

Issues in the milestone are picked by ascending number. Ready means the
`status:ready` label is set; blocked deps are parsed from
`Blocked-by: #NN, #MM` in the issue body. A dep is "done" iff its issue
is closed.

## Subcommands

| Command                       | Behavior                                                       |
|-------------------------------|----------------------------------------------------------------|
| `ralph once [<milestone>]`    | One iteration. Exit 20 = COMPLETE, 21 = BLOCKED.               |
| `ralph run <N> [<milestone>]` | Up to N iterations; halts on COMPLETE / BLOCKED / failure.     |
| `ralph ls`                    | List PRDs (fs) or open milestones (github).                    |
| `ralph ls <prd\|milestone>`   | Show issue queue with status and next pick (`→`).              |
| `ralph status`                | Show host + sandbox processes; flag stuck children.            |
| `ralph kill`                  | `pkill` ralph + `sbx stop` the sandbox.                        |

`<milestone>` is required when `BACKEND=github`; ignored for `fs` backend.


## Agent CLI and sandboxing

A ralph engagement uses one configured **Agent CLI**. `AGENT_CLI` selects the
adapter (`claude`, `codex`, or `pi`), `AGENT_CMD` supplies the executable or
wrapper, and `AGENT_ARGS` carries optional extra adapter arguments.
`MODEL_CLASS=low` selects adapter defaults (`claude` -> `sonnet`, `codex` ->
`gpt-5.4-mini`); set `MODEL` to override explicitly. Pi relies on external provider
configuration, so ralph omits `--model` unless `MODEL` is set.

Sandboxing is ralph-level: wrap the whole Agent CLI in `sbx` via `AGENT_CMD`,
for example `AGENT_CMD="sbx run my-project -- claude"`. Provider-internal
sandbox flags are not the default isolation boundary; pass them only as explicit
opt-in adapter arguments when you need provider-specific behavior.

Each non-interactive iteration writes artifacts under
`.ralph-logs/<prd-or-milestone>/`:

- `iter-<N>-<timestamp>.jsonl` — adapter progress/event log
- `iter-<N>-<timestamp>.final.txt` — final assistant message used for
  `<promise>COMPLETE</promise>` / `<promise>BLOCKED</promise>` detection

## Config overrides

Read from `./.ralph.conf` (sourced as bash) or environment. Env wins
when both set.

### Common

| Key              | Default                          | Meaning                                       |
|------------------|----------------------------------|-----------------------------------------------|
| `AGENT_CLI`     | `claude`                         | Agent CLI adapter: `claude`, `codex`, or `pi`. |
| `AGENT_CMD`     | value of `AGENT_CLI`              | Executable or wrapper for the Agent CLI.      |
| `AGENT_ARGS`    | empty                             | Optional extra adapter args.                  |
| `MODEL_CLASS`   | `low`                             | Model Class; maps to adapter defaults.        |
| `MODEL`         | empty                             | Optional explicit model override.             |
| `CLAUDE_CMD`    | empty                             | Legacy compatibility alias for Claude only.   |
| `SANDBOX_NAME`  | auto from `AGENT_CMD`/`CLAUDE_CMD` | Sandbox to inspect/stop.                    |
| `TEST_CMD`      | `./run_tests`                     | Test command the agent runs each iteration.   |
| `LINT_CMD`      | `/lint`                           | Lint command (use `:` for no-op).             |
| `STUCK_CPU_SECS` | `180`                            | CPU-seconds threshold for `status` flagging.  |
| `MARKER_FILE`   | `.scratch/ACTIVE`                 | (fs) names the active PRD dir.                |
| `BACKEND`       | `fs`                              | `fs` or `github`.                             |

### GitHub backend

| Key                 | Default          | Meaning                                  |
|---------------------|------------------|------------------------------------------|
| `GH_REPO`           | gh-detected      | `owner/name`; passed as `--repo`.        |
| `GH_LABEL_READY`    | `status:ready`   | Label marking pickable issues.           |
| `GH_LABEL_BLOCKED`  | `status:blocked` | Label applied on iteration failure.      |

## Halt codes

`ralph once` (and per-iteration in `ralph run`) returns:

- `0` — keep going
- `20` — `<promise>COMPLETE</promise>` (queue drained)
- `21` — `<promise>BLOCKED</promise>` (unfinished work, nothing pickable)
- `10` — no active PRD marker (fs backend)
- other — Agent CLI invocation failure

## Tests

```bash
bash tests/pick_next_issue_spec.sh
```
