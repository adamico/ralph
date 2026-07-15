# Recipes

Shared configuration recipes for native `ralph init` (see
[ADR-0013](../docs/adr/0013-shared-recipes-for-native-init.md)). `install.sh`
symlinks this directory to `~/.ralph/recipes/`, where `ralph init` reads it.

`ralph init` combines **one environment recipe** and **one agent recipe** to
generate `.ralph.conf` and copy any harness files into the project.

## Layout

```
recipes/
  environments/<name>/   # test/lint harness + env.conf
  agents/<name>/         # agent.conf
```

## Environment recipes

An environment recipe configures how the agent tests and lints the project.

- `env.conf` — appended to `.ralph.conf`; sets `TEST_CMD` and `LINT_CMD`.
- Any other non-`.md`, non-`.conf` file (e.g. `run_tests`, `.sbx/build.sh`) is
  copied into the project (existing files are never overwritten).
- `README.md` / other `*.md` are documentation only — not copied.

`ralph init` auto-detects some environments (e.g. `app/main.rb` → `dragonruby`,
`littlejsengine` in `package.json` → `littlejs`) and otherwise shows a menu.

| Recipe          | Stack                    | Notes                                    |
|-----------------|--------------------------|------------------------------------------|
| `dragonruby`    | DragonRuby (Ruby)        | Sandbox build + dual-mode `run_tests`.   |
| `littlejs`      | LittleJS (node/vitest)   | Dual-mode `run_tests test\|lint`.        |
| `python-pytest` | Python                   | `pytest` + `ruff check`.                 |

## Agent recipes

An agent recipe configures which Agent CLI ralph drives. `agent.conf` sets:

- `AGENT_CLI` — adapter (`claude`, `codex`, `pi`, `antigravity`).
- `AGENT_CMD` — executable or wrapper (e.g. `sbx run claude --` for Docker).
- `AGENT_ARGS` — optional extra adapter args.
- `MODEL_CLASS` — cost/capability class (`low` by default).

| Recipe          | CLI    | Isolation                        |
|-----------------|--------|----------------------------------|
| `claude-local`  | claude | host binary                      |
| `claude-docker` | claude | `sbx run claude --` sandbox      |
| `codex-docker`  | codex  | `sbx run codex --` sandbox       |
| `rtk-local`     | rtk    | host binary                      |

## Adding a recipe

Drop a new directory under `environments/` or `agents/` following the same file
layout. Because `~/.ralph/recipes/` is a symlink to this repo, it is picked up
immediately — no reinstall. Local-only recipes can also be added directly under
`~/.ralph/recipes/` without committing them here.
