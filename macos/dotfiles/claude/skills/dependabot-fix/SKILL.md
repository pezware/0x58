---
name: dependabot-fix
description: >-
  Clear Dependabot alerts in pnpm monorepos (primary) and npm projects — triage
  direct vs transitive vulnerabilities, pick the right fix mechanism, and pass
  supply-chain maturity gates (minimumReleaseAge / min-release-age) without
  disabling them. Use when clearing GitHub Dependabot alerts.
---

# Dependabot Fix Workflow

Patterns for clearing dependabot alerts in pnpm monorepos (primary focus) and npm projects (contrasted inline where the two ecosystems diverge): triaging direct vs transitive vulnerabilities, picking the right fix mechanism, and getting through supply-chain maturity gates without disabling them.

## When to use

- A GitHub repo has open alerts at `/security/dependabot` you need to clear
- An advisory points at a transitive dep (`pnpm why` shows it nested) and you can't bump it directly
- Installing the patched version is blocked by `minimumReleaseAge` (pnpm) / `min-release-age` (npm 11.10+) because the fix is fresher than the maturity floor
- A workspace is part of a pnpm monorepo and you need to understand which `package.json` files actually contribute to `pnpm-lock.yaml`
- An npm project (no workspaces, single `package-lock.json`) needs the same hygiene — the override and quarantine mechanisms exist but the **per-package exclude is pnpm-only** (see the pattern file's npm callout)

## Patterns

- [pnpm-dependabot-workflow.md](patterns/pnpm-dependabot-workflow.md) — End-to-end recipe: triage → fix → verify, including the override and release-age-exclude tricks. Includes an explicit npm-vs-pnpm contrast in the bypass section so the pnpm-style `minimum-release-age-exclude[]=` syntax isn't accidentally carried into an npm `.npmrc` (where it silently no-ops).
