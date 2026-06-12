# Docker Image Slimming

## Problem

Multi-stage Docker builds can still ship test files, dev scripts, and build artifacts into production images when `COPY --from=build` uses broad directory targets.

## Audit Steps

1. **Check what the CMD needs** — trace the entrypoint to understand the minimum runtime footprint:
   ```bash
   grep -E '^CMD|^ENTRYPOINT' Dockerfile
   # e.g., CMD ["node", "./dist/src/index.js"] → only dist/src/ is the entrypoint
   ```

2. **Measure what's actually in dist/** — compare needed vs shipped:
   ```bash
   du -sh dist/*/
   # dist/src/       3.3M  ← needed
   # dist/tests/     4.0M  ← not needed
   # dist/scripts/   misc  ← not needed
   ```

3. **Narrow COPY to explicit subdirectories** — replace broad `COPY dist ./dist` with individual directories.

## Gotcha: tsc-alias creates cross-directory dependencies

When using `tsc-alias` (or similar path-rewriting tools), TypeScript aliases like `@prisma_schema/prisma` get rewritten to relative paths in compiled JS: `require("../../../../prisma/prisma")`.

If the alias source is outside `src/` (e.g., `prisma/prisma.ts` at the project root), the compiled path escapes `dist/src/` and lands in `dist/prisma/`. This is invisible in TypeScript source but breaks at runtime if you only copy `dist/src/`.

**Always verify with the compiled output, not the TypeScript source:**
```bash
# Find all requires that resolve outside dist/src/
find dist/src -name '*.js' | while read -r file; do
  dir=$(dirname "$file")
  grep -oh 'require("[^"]*")' "$file" | grep '\.\.\/' | \
    sed 's/require("//;s/")//' | while read -r relpath; do
      resolved=$(cd "$dir" && python3 -c \
        "import os.path; print(os.path.normpath('$relpath'))" 2>/dev/null)
      echo "$resolved" | grep -qv '^src/' && echo "OUTSIDE: $resolved (from $file)"
    done
done
```

## Pattern: Explicit allowlist COPY

```dockerfile
# Instead of: COPY --from=build /app/dist ./dist
COPY --from=build --chown=node:node /app/dist/src ./dist/src
COPY --from=build --chown=node:node /app/dist/prisma ./dist/prisma
COPY --from=build --chown=node:node /app/dist/network ./dist/network
COPY --from=build --chown=node:node /app/dist/package.json ./dist/package.json
```

New directories added to `dist/` in the future won't accidentally ship — they must be explicitly added to the Dockerfile.

## Alternative: Clean in build stage

If explicit COPY gets unwieldy (too many subdirs), delete unwanted dirs before copying:
```dockerfile
# In build stage, after compilation:
RUN rm -rf dist/tests dist/test-reports dist/scripts

# In runtime stage, copy the cleaned dist:
COPY --from=build --chown=node:node /app/dist ./dist
```

Trade-off: denylist (may miss new unwanted dirs) vs allowlist (may miss new needed dirs). Prefer allowlist when practical.
