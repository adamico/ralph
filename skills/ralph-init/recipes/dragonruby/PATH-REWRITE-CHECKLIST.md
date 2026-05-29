# DragonRuby Recipe Path-Rewrite Checklist

When importing this recipe into a port's `.sbx/` directory, these paths require rewriting:

## Files to Import

- `build.sh` → `.sbx/build.sh`
- `dr-update-sandbox` → `.sbx/dr-update-sandbox`
- `run_tests` → (port root, executable)

## Path Rewrites in `build.sh`

| Location | Original | Rewrite | Reason |
|----------|----------|---------|--------|
| Line 14 | `.ruby-version` | `.ruby-version` ✓ | Port-relative; no change needed |
| Line 15 | `Gemfile` | `Gemfile` ✓ | Port-relative; no change needed |
| Line 32 | `.sbx/dr-update-sandbox` | `.sbx/dr-update-sandbox` ✓ | Relative to port root; no change |
| Line 115 | `DR_LINUX_ARM64_SRC` env var | `$DR_LINUX_ARM64_SRC` ✓ | Host path; passed at runtime |

**Sandbox Names & Template Tags:**
- `SANDBOX_NAME` defaults to `claude-locomotion` → should become `<repo>-dragonruby`
- `TEMPLATE_TAG` defaults to `dragonruby` → follows naming convention, no change needed

## Path Rewrites in `dr-update-sandbox`

| Location | Path | Reason |
|----------|------|--------|
| Line 48 | `/opt/dragonruby-linux-arm64` | Sandbox-internal path (baked by `build.sh`); no change needed |
| Line 86 | `dragonruby-${OS}` | Relative to target dir; no change needed |
| Line 86 | `dragonruby-macos/mygame` | Port-relative (host engine source); no change needed |

## Path Rewrites in `run_tests`

| Location | Original | Rewrite | Reason |
|----------|----------|---------|--------|
| Line 9 | `"$(dirname "$0")"` | `"$(dirname "$0")"` ✓ | Script-relative; works from any port |
| Line 12 | `dragonruby-macos` | `dragonruby-macos` ✓ | Port-relative (host engine); no change |
| Line 29 | `/tmp/loco-test` | `/tmp/<repo>-test` | Remote mode; avoid collisions across ports |
| Line 39 | `github.com/adamico/locomotion` | (configurable) | Remote clone source; documented as `SANDBOX_CLONE` var |

**Environment Variables (runtime configurable):**
- `DR_TEST_SOURCE` — `local` (default) or `remote`
- `DR_TEST_REF` — git ref override for remote clones (default: current branch or `main`)
- `SDL_VIDEODRIVER=dummy` — ensures headless operation in sandbox

## Sandbox Integration

All scripts assume:
- `sbx` CLI available in `$PATH`
- Sandbox names follow `<repo>-<console>` pattern (e.g., `myrepo-dragonruby`)
- Template tags follow `<console>` pattern (e.g., `dragonruby`)
- `.ruby-version` and `Gemfile` exist in port root
- `dragonruby-macos/` engine available in port root (for host local tests)
- `DR_LINUX_ARM64_SRC` env var points to unzipped linux-arm64 engine (for `build.sh`)

## Verification

After rewriting into a port:
```bash
shellcheck .sbx/build.sh .sbx/dr-update-sandbox run_tests
```

All scripts must pass shellcheck with no errors.
