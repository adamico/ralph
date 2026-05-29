# ADR Context: DragonRuby Sandbox Recipe

## ADR-0016: SBX Template Build Pattern

**Context:** Building sandbox templates (immutable snapshots) instead of provisioning on-demand.

**Key Points:**
- Templates are built once, cached, and reused across test runs
- `build.sh` creates a named sandbox, provisions dependencies (CRuby, gems, DragonRuby binary), then snapshots it
- Snapshots are named by `TEMPLATE_TAG` (e.g., `dragonruby`) and stamped with a build artifact
- Reduces per-iteration setup cost: no re-downloading, no re-compiling

**Relevant to Recipe:**
- `build.sh` implements template-build workflow
- `SANDBOX_NAME` is the ephemeral scratch sandbox used during build
- `TEMPLATE_TAG` is the persistent, reusable snapshot created at the end
- Pre-baked DragonRuby binary avoids isolated-sandbox credential problems (no downloads in sandbox)
- Bundler cache is cleared to prevent etag-related snapshot issues

**Design Decision:**
- Why sandbox templates? Test reproducibility + speed. Snapshot captures exact state so tests run on identical environment every time, without re-provisioning overhead.

---

## ADR-0022: Remote Fresh-Clone Test Harness

**Context:** Two modes of test execution — local (host machine) and remote (sandbox).

**Key Points:**
- **Local mode** (`DR_TEST_SOURCE=local`): Use host macOS engine in-place. Fast iteration during development. Requires macOS + native DragonRuby binary.
- **Remote mode** (`DR_TEST_SOURCE=remote`): Fresh clone + linux-arm64 engine in sandbox. Used in CI/CD or when host is unavailable.
- `run_tests` script auto-detects mode via `DR_TEST_SOURCE` env var
- Remote mode clones from `github.com/adamico/locomotion` (configurable via `SANDBOX_CLONE` var), provisions engine via `dr-update`, runs tests in isolated sandbox
- `dr-update` provisioner is baked into template during `build.sh` so remote clones don't need network access for engine

**Relevant to Recipe:**
- `run_tests` implements dual-mode harness
- `dr-update-sandbox` is the provisioner script, copied into sandbox during template build
- Engine provisioning is idempotent (no-op if engine already exists)
- `mygame/` syncing ensures test project is in-sync across host/sandbox

**Design Decision:**
- Why two modes? Local mode supports fast human iteration (no docker overhead). Remote mode ensures CI/CD isolation + reproducibility, and avoids host machine dependencies.

---

## Source References

All scripts are from `github.com/adamico/locomotion`:
- `.sbx/build.sh` (158 lines) — Template build orchestration
- `.sbx/dr-update-sandbox` (101 lines) — Sandbox-internal engine provisioner
- `run_tests` (60 lines) — Dual-mode test harness

These are canonical implementations that have been tested across multiple ports (ruby + dragonruby).

---

## Integration Notes

When porting to a new console (e.g., `pico-dragonruby`, `fantastico-dragonruby`):

1. Copy these three files into the port's `.sbx/` directory (and `run_tests` to port root)
2. Review PATH-REWRITE-CHECKLIST.md for required customizations
3. Ensure `.ruby-version` and `Gemfile` exist in port root (or adjust `build.sh` line 14–15)
4. Provide `DR_LINUX_ARM64_SRC` env var pointing to unzipped linux-arm64 engine
5. Run `shellcheck` on all three files to verify correctness
6. Test locally: `DR_TEST_SOURCE=local ./run_tests`
7. Test remotely (CI): `DR_TEST_SOURCE=remote ./run_tests`
