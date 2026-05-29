---
name: ralph-init
description: Scaffold a .ralph.conf for the current repo. Detects primary language (or, in a monorepo, multiple game-engine ports under build/<console>/), suggests TEST_CMD, LINT_CMD, BACKEND, MODEL, and CLAUDE_CMD. Optionally guides Docker/sbx sandbox setup so AFK runs execute in an isolated container (host machine is NOT used for tests/lint — the container is). Use when user says "ralph init", "set up ralph", "create .ralph.conf", or wants to configure ralph for a new project (single-engine or multi-engine monorepo).
---

# ralph-init

## Goal

Create or update `.ralph.conf` so ralph can drain issues for this repo.

Two modes:

- **Single-engine repo** — one `.ralph.conf` at the root. (Original behavior.)
- **Monorepo of game-engine ports** — multiple engines live under
  `build/<console>/`, each with its own test harness and its own
  Docker/sbx story. Each port gets its **own standalone** `.ralph.conf`;
  the root gets an engine-agnostic config for cross-cutting work.

**Mode detection:** if more than one engine marker is found (see the
[marker table](#engine-detection)), or ports exist under `build/*/`,
use the [monorepo flow](#monorepo-multi-engine-flow). Otherwise use the
[single-engine flow](#single-engine-flow).

### Why no ralph code change is needed

`TEST_CMD` and `LINT_CMD` are **never executed by ralph** — they are
interpolated as *text* into the Claude prompt ("Run tests via:
$TEST_CMD"). The agent runs them. `.ralph.conf` is sourced relative to
**cwd** (`bin/ralph` sources `./.ralph.conf`). So per-port configs and
per-engine runs work today with zero changes to `bin/ralph`: you `cd`
into a port dir (or stay at root) and run ralph there.

`CLAUDE_CMD`/`SANDBOX_NAME`, by contrast, *are* executed — they wrap the
**entire** claude invocation for a run. One run therefore wraps one
sandbox, which is why a monorepo runs **per-engine**, not as one mixed
queue.

---

## Single-engine flow

1. **Check existing** — if `.ralph.conf` exists, read it and ask whether to update or abort.

2. **Detect language & tooling**:
   - Run `git remote -v` — if github.com URL found → `BACKEND=github`
   - Detect primary language by scanning file extensions (`.js`/`.ts`/`.html` → JS, `.py` → Python, `.rs` → Rust, `.go` → Go, etc.)

   **TEST_CMD detection** — check in this order:

   | Condition | TEST_CMD |
   |---|---|
   | `package.json` has `test` script | `npm test` |
   | `package.json` has `vitest` dep | `npx vitest run` |
   | `Makefile` has `test` target | `make test` |
   | `pytest.ini` / `pyproject.toml` w/ pytest | `pytest` |
   | `Cargo.toml` | `cargo test` |
   | `go.mod` | `go test ./...` |
   | `mix.exs` | `mix test` |
   | `build.gradle` / `pom.xml` | `./gradlew test` / `mvn test` |
   | `tests/*.sh` | `bash tests/*.sh` |
   | `run_tests` (executable) | `./run_tests` |
   | **Nothing found + JS detected** | propose installing Vitest (see JS Setup below) |
   | **Nothing found + Python detected** | propose installing pytest |
   | **Nothing found** | `:` but warn user |

   **LINT_CMD detection** — check in this order:

   | Condition | LINT_CMD |
   |---|---|
   | `.eslintrc*` or `eslint` in package.json | `npx eslint .` |
   | `Makefile` has `lint` target | `make lint` |
   | `.flake8` / `ruff.toml` | `ruff check .` or `flake8 .` |
   | `Cargo.toml` | `cargo clippy` |
   | primary language is bash (`.sh` files dominant, no other lang) | `shellcheck bin/* tests/*.sh` (propose `brew install shellcheck` / `apt install shellcheck` if not found) |
   | **Nothing found + JS detected** | propose installing ESLint (see JS Setup below) |
   | **Nothing found + Python detected** | propose installing ruff |
   | **Nothing found** | `:` but warn user |

   **JS Setup** — if JS/TS project has no test or lint tooling, offer to install gold-standard defaults:
   - Test: `npm install --save-dev vitest` → `TEST_CMD="npx vitest run"`
   - Lint: `npm install --save-dev eslint @eslint/js` + generate `eslint.config.js` → `LINT_CMD="npx eslint ."`
   - Ask user: "Install Vitest + ESLint now? (recommended)" before running npm install.

3. **Ask: Docker sandbox?** — after detecting TEST_CMD/LINT_CMD, ask:
   > "Run AFK sessions in a Docker sandbox? (isolated container; host machine not used for tests/lint)"

   - If **no** → skip to step 4 with `CLAUDE_CMD="claude"`
   - If **yes** → follow [Docker Sandbox Setup](#docker-sandbox-setup) below, then return to step 4

4. **Show proposed config** — print the full `.ralph.conf` content to user before writing.

5. **Ask confirmation** — "Write this to `.ralph.conf`?"

6. **Write file** — use Write tool. Remind user to add `.ralph.conf` to `.gitignore` if not already there.

7. **Verify** — run `ralph ls` to confirm ralph can load the config without errors.

---

## Monorepo multi-engine flow

A single skill invocation scaffolds every detected port:

> **scan → confirm → loop each port → root config → summary**

Idempotent: a port that already has a `.ralph.conf` is reported as
configured and **skipped** unless the user chooses to update it.

### Orchestrator (main flow)

The single top-level procedure for a monorepo. Run top-to-bottom in **one**
skill invocation; each step links to its detailed subsection below.

1. **Scan** — run [Engine detection](#engine-detection). Yields the ordered,
   deduped `(port-dir, console, tier)` list.
2. **Confirm** — print the detected set and ask to proceed. The user may drop or
   correct entries; abort writes nothing.
3. **Loop ports** — for each `(port, console, tier)` **in order**:
   - **Idempotency:** if `<port>/.ralph.conf` already exists, report it
     *configured* and ask "update? (default **skip**)". Skip unless the user
     opts in.
   - Otherwise **dispatch by tier** to the matching recipe and record the
     outcome (scaffolded / skipped / failed):

     | Tier | Recipe |
     |---|---|
     | host-fallback (pico8, picotron) | [Per-port config → host-fallback](#per-port-config-all-tiers) |
     | standard (littlejs)             | [Per-port config → standard](#per-port-config-all-tiers) |
     | mature-external (dragonruby)    | [dragonruby guided import](#mature-external-recipe-dragonruby-guided-import) |
4. **Root config** — offer the
   [root engine-agnostic config](#root-engine-agnostic-config) **last**, for
   cross-cutting work.
5. **Summary** — print the per-port [Summary](#summary): what was scaffolded,
   what was skipped (already configured), and what remains TODO.

### Engine detection

Scan `build/*/` first; **fall back** to a general marker-scan at
max-depth 3 when nothing engine-like is found under `build/`. Each
directory containing a marker is one engine root. **Suppress nested
matches** — never register an engine under an already-matched engine
root (e.g. a dragonruby engine tree's inner files must not re-trigger).

| Console | Marker | Tier |
|---|---|---|
| **dragonruby** | a `dragonruby-*/` dir, or `app/main.rb` (i.e. a `mygame/app/main.rb`) | mature-external |
| **littlejs** | `package.json` containing `littlejsengine` | standard |
| **pico8** | `*.p8` cart files | host-fallback |
| **picotron** | `*.p64` cart files | host-fallback |

Output an ordered, deduped list of `(port-dir, console, tier)`.

**Confirm with the user** — print the detected set and ask to proceed
before writing anything. Let the user correct it.

### Per-port config (all tiers)

Each port gets a **standalone** `.ralph.conf` — **no inheritance** from
the root config (sourcing a parent is a hidden-dependency / wrong-cwd
footgun; the tiny duplication of `BACKEND`/`MODEL` is worth the
isolation). If the file already exists, prompt to overwrite (default
skip).

**Naming convention:** sandbox template tag and `SANDBOX_NAME` =
`<repo>-<console>`; for dockerized tiers `CLAUDE_CMD="sbx run
<repo>-<console> --"`.

**Milestone convention:** document `<console>-<feature>` (e.g.
`dragonruby-articulated-rig`) as a comment. The milestone is a runtime
positional arg to `ralph once <milestone>`, **not** stored in config.

Shared header for every port config:

```bash
# Per-port standalone config for <repo>/<console>.
# No inheritance from parent — each port config is self-contained.
# Milestone naming convention: <console>-<feature> (e.g. <console>-my-feature).
# Milestone is a runtime arg to 'ralph once', not stored in config.

BACKEND="github"
MODEL="haiku"
```

Then the tier-specific tail:

**host-fallback (pico8, picotron):**

```bash
# Host fallback: no sandbox yet. CLAUDE_CMD runs on host; TEST_CMD is a stub.
# TODO: implement code-judo Docker recipe (see dragonruby ADR-0016/ADR-0022).
CLAUDE_CMD="claude"
TEST_CMD=":"
LINT_CMD=":"
```

Also write a **stub** `.sbx/build.sh` (chmod +x) for these consoles:

```bash
#!/bin/bash
# TODO: implement code-judo Docker recipe for pico8/picotron.
# Stub placeholder; full sandbox build recipe not yet implemented.
# See the dragonruby recipe (ADR-0016 template build, ADR-0022 clone harness).
set -uo pipefail
echo "TODO: sandbox build recipe not yet implemented for this console" >&2
exit 0
```

**standard (littlejs):** — use bundled template from `recipes/littlejs/`.

1. **Ensure vitest + eslint** in the port's `package.json`. If missing, offer:
   ```bash
   npm install --save-dev vitest eslint @eslint/js
   ```
   Ask user: "Install Vitest + ESLint now? (recommended)" before running.

2. **Copy bundled template** to the port (no Dockerfile — the sandbox is a bare
   `node:20`; rewrite the `LITTLEJS_` env prefix in `run_tests` to the port's
   `<ENGINE>_` prefix, e.g. `OBSI_`):

   | Source (bundled)        | Destination                 |
   |---|---|
   | `recipes/littlejs/build.sh` | `<port>/.sbx/build.sh` |
   | `recipes/littlejs/run_tests` | `<port>/run_tests` |

3. **Verify** — `shellcheck <port>/.sbx/build.sh <port>/run_tests` must pass clean.

4. **Emit config** — `<port>/.ralph.conf`. Test model (B): `run_tests` remote mode
   clones `origin/<branch>`, so the agent must **commit AND push before tests see
   its work**. State that in the conf header (`TEST_CMD` is prompt-text-only — it
   rides into the agent's prompt as text):

   ```bash
   # Tests run via run_tests remote mode: fresh clone of origin/<branch> in the
   # sandbox + clean linux `npm ci`. COMMIT AND PUSH before tests reflect changes
   # (ADR-0022: "WIP must be pushed to be testable"). Absolute path: agent cwd in
   # the sandbox is not the mount.
   CLAUDE_CMD="sbx run <repo>-littlejs --"
   TEST_CMD="<ENGINE>_TEST_SOURCE=remote <abs-path>/run_tests test"
   LINT_CMD="<ENGINE>_TEST_SOURCE=remote <abs-path>/run_tests lint"
   ```

5. **Optional: Build sandbox now?** — Ask user whether to run `.sbx/build.sh`
   immediately (`SANDBOX_NAME=<repo>-littlejs bash .sbx/build.sh`) or defer to
   first ralph run. Building now validates the setup; deferring lets ralph batch
   multiple ports. If building, report success/failure.

**mature-external (dragonruby):** — see the dragonruby guided import below.

### mature-external recipe: dragonruby guided import

Drives the import from the **bundled `recipes/dragonruby/`** resource
(path-rewrite checklist + reference scripts; ADR-0016 template build,
ADR-0022 clone harness). **Show every rewritten file to the user for
confirmation before writing it — never write unconfirmed.**

`<repo>` = basename of the git toplevel; `<port>` = the dragonruby port
path relative to repo root (`build/dragonruby` in a monorepo, `.`
standalone).

**0. Gather context.**

```sh
REPO="$(basename "$(git rev-parse --show-toplevel)")"
REMOTE="$(git remote get-url origin 2>/dev/null || git remote -v | awk 'NR==1{print $2}')"
```

`REPO` drives the `<repo>-dragonruby` naming and `/tmp` dir; `REMOTE` is
the monorepo clone URL used by `run_tests` remote mode (it clones the
**monorepo**, not locomotion).

**1. Clone the source of record** — `adamico/locomotion` to a scratch
dir, then copy three files into the port:

| Source (in clone)        | Destination                      |
|--------------------------|----------------------------------|
| `.sbx/build.sh`          | `<port>/.sbx/build.sh`           |
| `.sbx/dr-update-sandbox` | `<port>/.sbx/dr-update-sandbox`  |
| `run_tests`              | `<port>/run_tests` (executable)  |

If locomotion is unreachable, fall back to the bundled
`recipes/dragonruby/` copies — they still need the rewrites below.

**2. Apply path rewrites**, then show each file before writing. Full
anchor table in `recipes/dragonruby/PATH-REWRITE-CHECKLIST.md`.

`run_tests`:

| Anchor (locomotion source)                            | Rewrite                                              |
|-------------------------------------------------------|------------------------------------------------------|
| `SANDBOX_CLONE="/tmp/loco-test"`                      | `SANDBOX_CLONE="/tmp/<repo>-dragonruby"`             |
| `git clone https://github.com/adamico/locomotion ...` | clone `$REMOTE` (monorepo remote, auto-detected)     |
| `dr-update .`                                         | `dr-update <port>` (e.g. `dr-update build/dragonruby`) |
| final `cd "dragonruby-${DR_OS}"`                      | `cd "<port>/dragonruby-${DR_OS}"` (port-relative)    |

`build.sh`:

| Anchor                                              | Rewrite                  |
|-----------------------------------------------------|--------------------------|
| `SANDBOX_NAME="${SANDBOX_NAME:-claude-locomotion}"` | `…:-<repo>-dragonruby}`  |
| `TEMPLATE_TAG="${TEMPLATE_TAG:-locomotion-ruby}"`   | `…:-<repo>-dragonruby}`  |

`dr-update-sandbox`: no rewrites (paths are sandbox-internal or
port-relative).

**3. Ensure `.ruby-version` + `Gemfile`** in the port root — `build.sh`
fails without both. Missing → create (prompt for the ruby version,
defaulting to locomotion's `.ruby-version`). Present → show and prompt
before modifying.

**4. Prompt for `DR_LINUX_ARM64_SRC`** — host path to the unzipped,
licensed linux-arm64 engine that `build.sh` bakes (default
`~/Downloads/dragonruby-linux-arm64`).

**5. Verify** — `shellcheck <port>/.sbx/build.sh
<port>/.sbx/dr-update-sandbox <port>/run_tests` must pass clean. Fix any
rewrite that broke it.

**6. Emit config** — `<port>/.ralph.conf`:

```bash
CLAUDE_CMD="sbx run <repo>-dragonruby --"
TEST_CMD="DR_TEST_SOURCE=remote ./run_tests"
LINT_CMD="bundle exec rubocop"
```

### Root engine-agnostic config

Offered **last**, for cross-cutting issues (shell scripts, docs, build
orchestration) that aren't tied to one engine. `LINT_CMD` is
`shellcheck` when shell scripts dominate the repo, else a no-op `:`.

```bash
# Root engine-agnostic config for cross-cutting issues.
# Per-engine configs live in build/<console>/.ralph.conf.

BACKEND="github"
MODEL="haiku"
CLAUDE_CMD="claude"
TEST_CMD=":"
LINT_CMD="shellcheck"   # or ":" if shell scripts don't dominate
```

### Summary

After the loop, print a per-port summary: what was scaffolded, what was
skipped (already configured), and what remains TODO (host-fallback
Docker recipes, etc.).

---

## Known limitations

- **host-fallback tiers (pico8, picotron) have no sandbox recipe.** Their
  `.sbx/build.sh` is a stub and `TEST_CMD`/`LINT_CMD` are no-ops; `CLAUDE_CMD`
  runs on the host. A real code-judo Docker recipe (cf. dragonruby
  ADR-0016/ADR-0022) is not yet implemented.
- The monorepo flow assumes an interactive session — external repo access
  (locomotion), a licensed linux-arm64 binary, and npm/sbx availability. It is
  authored but not yet validated end-to-end against a live monorepo.

---

## Docker Sandbox Setup

Goal: create a named `sbx` sandbox whose container has the project's validated test/lint toolchain pre-installed. `CLAUDE_CMD` becomes `sbx run <name> -- claude`.

### Prerequisites check

```bash
which sbx        # must exist
docker info      # docker daemon must be running
```

If either fails, tell user what to install and stop here.

### Steps

1. **Choose sandbox name** — suggest repo dirname, e.g. `my-project`. User may override. In a monorepo, use `<repo>-<console>`.

2. **Determine base image** from detected language:

   | Language | Base image |
   |---|---|
   | JS/TS | `node:20` |
   | Python | `python:3.12` |
   | Rust | `rust:latest` |
   | Go | `golang:latest` |
   | Java | `eclipse-temurin:21` |
   | Unknown | `ubuntu:24.04` |

3. **Determine toolchain installs** from validated TEST_CMD / LINT_CMD:

   | Tool detected | Install command in container |
   |---|---|
   | `npm test` / `vitest` | already in node image; ensure `npm ci` runs |
   | `pytest` | `pip install pytest` (or `pip install -r requirements.txt`) |
   | `ruff` | `pip install ruff` |
   | `flake8` | `pip install flake8` |
   | `cargo test` / `clippy` | already in rust image |
   | `go test` | already in golang image |
   | `make` | `apt-get install -y make` |
   | ESLint | already via npm ci |

4. **Generate Dockerfile** at `.ralph/Dockerfile.sandbox`:

   ```dockerfile
   FROM <base-image>
   # Install project toolchain
   WORKDIR /workspace
   <install steps from table above>
   # claude-code CLI (required for AFK)
   RUN npm install -g @anthropic-ai/claude-code
   ```

   Show to user and ask to confirm before writing.

5. **Create sandbox**:

   ```bash
   sbx create <name> --dockerfile .ralph/Dockerfile.sandbox --mount .:/workspace
   ```

   If `sbx create` doesn't support `--dockerfile`, instruct user to run:
   ```bash
   docker build -t ralph-sbx-<name> -f .ralph/Dockerfile.sandbox .
   sbx create <name> --image ralph-sbx-<name> --mount .:/workspace
   ```

6. **Verify sandbox**:

   ```bash
   sbx run <name> -- <TEST_CMD>
   sbx run <name> -- <LINT_CMD>   # skip if LINT_CMD is ":"
   ```

   Both must exit 0. If they fail, diagnose (missing deps, wrong working dir) and fix Dockerfile before continuing.

7. **Set config vars**:
   ```
   CLAUDE_CMD="sbx run <name> -- claude"
   SANDBOX_NAME="<name>"
   ```

8. **Add `.ralph/` to `.gitignore`** if user doesn't want to commit the Dockerfile. Ask.

---

## ralph.conf format

```bash
# Per-project config for ralph. Sourced as bash from the repo root.

BACKEND="github"                        # or "fs"
CLAUDE_CMD="sbx run my-project -- claude"  # or just "claude"
SANDBOX_NAME="my-project"              # omit if not using sbx
MODEL="haiku"                           # haiku (fast/cheap AFK) or sonnet
TEST_CMD="npm test"                     # command that exits 0 on pass
LINT_CMD=":"                            # command that exits 0 on pass, or : for no-op
```

## Key variables reference

| Var | Default | Notes |
|---|---|---|
| `BACKEND` | `fs` | `github` uses GH Issues/Milestones |
| `CLAUDE_CMD` | `claude` | Prefix with `sbx run <name> --` for sandbox |
| `SANDBOX_NAME` | derived from CLAUDE_CMD | Set explicitly if CLAUDE_CMD doesn't contain `sbx run` |
| `MODEL` | `sonnet` | `haiku` recommended for AFK cost savings |
| `TEST_CMD` | `./run_tests` | Must exit 0 on pass |
| `LINT_CMD` | `/lint` | Use `:` for no-op |
| `STUCK_CPU_SECS` | `180` | Seconds before ralph flags hung process |
| `GH_REPO` | auto | Override if `gh` can't detect repo |
| `GH_LABEL_READY` | `ready-for-agent` | Label ralph picks up |
| `GH_LABEL_BLOCKED` | `blocked` | Label ralph stops on |
