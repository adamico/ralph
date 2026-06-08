# ADR-0003 — Tool-coupled skills ship in the ralph repo

**Status:** accepted

## Context

Before ralph supported multiple Agent CLIs, two ralph-adjacent skills both
lived in the personal `ai-skills` repo (symlinked into the legacy Claude skills
location, `~/.claude/skills`): `to-issues-gh` and the full 419-line `ralph-init`
(`SKILL.md` + `recipes/dragonruby/`). Meanwhile this repo carried a
divergent 67-line stub `SKILL.md` and a duplicate (then staged-for-deletion)
`recipes/`. So `ralph-init` was both *already homed in `ai-skills`* and drifting
against a stub here.

A skill must physically live under `~/.claude/skills/` (or a plugin dir) to be
invokable, so "where is the source of truth?" and "how does it get installed?"
are distinct questions. The deeper question: which ralph-adjacent skills belong
in *this* repo versus the shared `ai-skills` collection?

## Decision

The dividing line is **coupling to the binary**:

- Skills that **configure or operate `bin/ralph`** — version-locked to its
  config schema (`.ralph.conf`) and this repo's ADRs — live in
  `<repo>/skills/<name>/`. `install.sh` symlinks each into
  `~/.claude/skills/<name>` (guarded: only when `~/.claude/skills` exists).
  `ralph-init` is the first such skill.
- Skills that **produce artifacts usable without the binary** stay in
  `ai-skills`. `to-issues-gh` emits GitHub issues a human *or* ralph can drain,
  so it is not tool-coupled despite following ralph's GitHub conventions.

The repo is canonical; the installed location is a symlink, never an edited copy.

## Rationale

- `ralph-init`'s recipes cite ADRs and its scaffolding tracks `bin/ralph`'s
  config schema. Source and tool must move together; a clone should yield a
  working skill without a second fetch.
- A symlink makes drift structurally impossible — the exact failure mode that
  produced two divergent `SKILL.md` files.
- The coupling test gives a reusable rule for the next ralph-adjacent skill,
  instead of re-litigating placement each time.
- `skills/<name>/` (not a root-level `SKILL.md`) keeps the repo legible as a
  *tool* repo and scales to a second tool-coupled skill.

## Consequences

- `ralph-init` moves out of `ai-skills` into `<repo>/skills/ralph-init/`
  (SKILL.md + `recipes/`); the removal is committed in `ai-skills`. The root
  stub `SKILL.md` here is deleted; the staged `recipes/` deletion is abandoned
  (those files relocate under the skill dir).
- The existing `~/.claude/skills/ralph-init` symlink is repointed from
  `ai-skills` to this repo; `install.sh` gains a guarded
  `ln -sfn "$SRC_DIR/skills/ralph-init" "$HOME/.claude/skills/ralph-init"`.
- Two ralph-flavored skills live in two homes by design — justified by the
  coupling line, not an inconsistency to fix.
- Installing `ralph` on a host without the legacy Claude skills directory skips
  the symlink rather than failing.
