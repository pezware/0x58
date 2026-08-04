# Clearing Dependabot Alerts in a pnpm Monorepo

## Problem

GitHub flags vulnerabilities in `pnpm-lock.yaml`. The fix mechanism depends on **whether the vulnerable package is a direct or transitive dep**, and a supply-chain maturity gate (`minimumReleaseAge`) often blocks the freshest patches because they're younger than the configured floor.

## Workflow

### 1. Pull the alert list

```bash
gh api /repos/<owner>/<repo>/dependabot/alerts --jq '[.[] | select(.state == "open") | {
  number,
  severity: .security_advisory.severity,
  package: .dependency.package.name,
  manifest: .dependency.manifest_path,
  summary: .security_advisory.summary,
  vulnerable_version: .security_vulnerability.vulnerable_version_range,
  patched_version: .security_vulnerability.first_patched_version.identifier
}]'
```

Group by package — multiple alerts often resolve to a single version bump.

### 2. Classify direct vs transitive

```bash
pnpm why <package>      # walks dep tree, shows who pulls it in
grep '"<package>"' --include='package.json' -rn .
```

- **Direct** = declared in some workspace's `package.json` → bump there.
- **Transitive** = only nested under another dep → use `pnpm.overrides` in the **root** `package.json`.

### 3. Identify which workspaces matter

Only `package.json` files registered in `pnpm-workspace.yaml` contribute to `pnpm-lock.yaml`. Anything outside (templates, examples, archived services) isn't scanned by dependabot via the lockfile.

```bash
awk '/^importers:/,/^packages:/' pnpm-lock.yaml | grep -E "^  [^ ]"
```

Compare against `pnpm-workspace.yaml`. Bumps in unlisted dirs are no-ops for the alert.

### 4. Apply the fix

**Direct dep** — edit each workspace's `package.json`:
```diff
- "hono": "^4.12.14",
+ "hono": "^4.12.18",
```

**Transitive dep** — root `package.json`:
```json
"pnpm": {
  "overrides": {
    "fast-uri": ">=3.1.2"
  }
}
```

Prefer `>=X.Y.Z` over pinned `X.Y.Z` so future patches don't require re-editing.

### 5. Handle the release-age gate

If `pnpm install` fails with `ERR_PNPM_NO_MATURE_MATCHING_VERSION`, the patch is fresher than the configured `minimumReleaseAge` (e.g., 5 days). **Do not lower the gate** — it's a supply-chain defense against malicious/yanked releases. Add a per-package exception in `.npmrc`:

```ini
# TODO: remove after YYYY-MM-DD when <pkg> <version> matures past min-release-age (<CVE summary>)
minimum-release-age-exclude[]=<pkg>
```

The dated TODO makes the exception auditable and self-expiring. The expiry date is `release_date + minimumReleaseAge_days`.

> **⚠️ npm is not pnpm — the bypass differs.**
>
> The `minimum-release-age-exclude[]=` config above is **pnpm-only**. npm (11.10+) only defines
> `min-release-age` and rejects both `min-release-age-exclude` and `minimum-release-age-exclude`
> with `npm error '<name>' is not a valid npm option`. There is **no per-package exemption list
> in npm**. To bypass the gate in an npm project, use a CLI override on the single install:
>
> ```bash
> npm install <pkg>@<version> --min-release-age=0
> ```
>
> Verified against npm 11.14.1 `@npmcli/config/lib/definitions/definitions.js`: only
> `min-release-age` is defined, and it is `exclusive: ['before']`. Putting a pnpm-style
> exclude line into an npm project's `.npmrc` will **silently no-op** because npm doesn't
> recognize the key — meaning the gate stays in force when you thought you'd bypassed it.
> The mistake is hard to spot in review (the line *looks* like valid config) and is a
> recurring AI-reviewer hallucination — fact-check against the actual cli source, not
> web-query summaries.

### 6. Verify

```bash
pnpm install                                # regenerates lockfile
grep -E "^  (<pkg1>|<pkg2>)@" pnpm-lock.yaml | sort -u
```

Confirm only the patched version appears. Run `pnpm type-check` and unit tests in the affected workspaces — security patches occasionally tighten APIs in subtle ways (e.g., stricter JWT validation).

## Key Insights

- **Templates outside the workspace are invisible to dependabot** but visible to consumers who copy them. If a template's deps drift, the alert backlog moves downstream silently. Audit non-workspace templates manually when fixing the main workspaces.
- **`pnpm why` is authoritative for the dep tree**, not `package.json` grep. A package can appear in `package.json` as a `peerDependency` and still be transitively pulled by something else with a different version range.
- **Override versions use semver ranges**, not pinned versions. `">=3.1.2"` is correct; `"3.1.2"` blocks future patches. Match the existing override style in the repo for consistency.
- **The release-age gate is a feature, not friction**. The cleanest way to bypass it is per-package exclusion with a dated TODO — never by lowering the global floor.

- **npm and pnpm release-age configs are *not* interchangeable.** pnpm uses `minimumReleaseAge` **in minutes** (10080 = 7 days) with per-package `minimumReleaseAgeExclude`. npm uses `min-release-age` **in days** (`min-release-age=7`) and is `exclusive: ['before']`. Getting the unit backwards is the quiet failure: `minimumReleaseAge: 7` in a pnpm config looks configured and buys seven *minutes*. Mixing the syntaxes is the other one — a pnpm-style exclude line in an npm `.npmrc` silently no-ops, because npm rejects unknown keys at use-time, not parse-time.

- **Version floors, verified on npm 12.0.2 / pnpm 11.19 (2026-08-04).** `min-release-age` needs **npm ≥ 11.10**; below that npm stores the key, echoes it back from `npm config get`, and ignores it — so `npm config get` returning a value proves nothing. Assert against `npm config ls -l | grep release-age`, which lists what *that* npm actually knows. **npm 12 added `min-release-age-exclude`**, so the "npm has no exclude list" limitation above no longer holds on 12+; check before designing around its absence. pnpm 11 defaults `minimumReleaseAge` to 1440 but **non-strict** — it degrades rather than fails, so set `minimumReleaseAgeStrict: true` if you want enforcement.

- **On the devbox the gate lives in `~/.config/pnpm/config.yaml`, not `~/.npmrc`.** `~/.npmrc` is on the agent sandbox's credentials deny list, so a cooldown written there is unreadable by the actor it exists to constrain. pnpm 11 keeps non-auth settings in `config.yaml`, which is not denied — that is what makes the gate apply to agent-run installs. For npm specifically the durable answer is a project-level `.npmrc` committed in the repo, which is read regardless of sandbox rules and protects CI and teammates too.

## Gotcha: Lockfile-only changes still need a commit

`pnpm install` updates `pnpm-lock.yaml` even when `package.json` is unchanged (e.g., overrides take effect via lockfile resolution alone). Always `git add pnpm-lock.yaml` along with the manifest edits.

## Gotcha: Pre-commit hooks may run the full test suite

Husky + lint-staged setups often trigger `pnpm test:unit` on commit. Security bumps that touch many workspaces will slow this down significantly — budget time, don't `--no-verify`.
