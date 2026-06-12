# npm Package Hygiene

## Problem

Without explicit configuration, `npm publish` includes everything not in `.gitignore` — leaking TypeScript source, test files, eslint configs, and tsconfig into published packages.

## Audit Steps

1. **Find publishable packages** — any `package.json` without `"private": true`:
   ```bash
   find . -name package.json -not -path '*/node_modules/*' \
     -exec sh -c 'jq -r "select(.private != true) | .name" "$1" 2>/dev/null' _ {} \;
   ```

2. **Simulate what ships** — `npm pack --dry-run` shows exactly what would be published. Run this for every non-private package.

3. **Check for the `"files"` allowlist** — this is the recommended approach:
   ```json
   "files": ["dist", "!dist/**/*.test.*"]
   ```
   The negation pattern is defense-in-depth: excludes test artifacts even if a stale build leaks them into `dist/`.

## Fix Priority

| Fix | Impact |
|---|---|
| `"files": ["dist"]` on libraries | Prevents source code leakage |
| `"private": true` on applications | Prevents accidental `npm publish` |
| `!dist/**/*.test.*` negation | Catches stale test artifacts in build output |

## Key Insight

npm has 3 mechanisms checked in priority order:
1. `"files"` field (allowlist, recommended)
2. `.npmignore` (blocklist, replaces `.gitignore` entirely)
3. `.gitignore` fallback (if neither above exists)

`package.json`, `README`, and `LICENSE` are always included regardless.

## Gotcha: `.gitignore` vs `"files"` conflict

If `.gitignore` excludes `dist/` (common) and there's no `"files"` field, npm falls back to `.gitignore` rules. This means `dist/` may be excluded from the package — the opposite of what you want. Always use `"files"` explicitly for publishable packages.
