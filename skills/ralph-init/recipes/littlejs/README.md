# LittleJS Recipe

Bundled recipe for the ralph-init skill: sandbox template build for LittleJS ports.

## Contents

- `build.sh` — Build the `<repo>-littlejs` sandbox template
- `Dockerfile` — Base image for the Node.js sandbox
- `README.md` — This file

## Quick Start

For a new LittleJS port (or any Node.js/Vitest project):

1. Ensure `package.json` exists with `littlejsengine` or equivalent
2. Ensure vitest and eslint are listed in `package.json` (or run the install step)
3. Run `./build.sh` from the port root to create the `<repo>-littlejs` sandbox

## Configuration

The skill generates a `.ralph.conf` for the port with:

```bash
CLAUDE_CMD="sbx run <repo>-littlejs --"
TEST_CMD="npx vitest run"
LINT_CMD="npx eslint ."
```

## Assumptions

- `package.json` exists in port root
- Node.js 20+ environment is suitable
- `sbx` CLI is installed and configured
- `docker` daemon is running

## References

- LittleJS: https://github.com/KilledByAPixel/LittleJS
- Vitest: https://vitest.dev
- ESLint: https://eslint.org
