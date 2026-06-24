---
name: production-readiness
description: >-
  Patterns and checklists for hardening Docker images, npm packages, and CI
  pipelines before production deployment. Use for pre-release housekeeping,
  Dockerfile bloat/leak review, npm package source-leak audits, or adding
  BuildKit cache mounts.
---

# Production Readiness Audit

Patterns and checklists for hardening Docker images, npm packages, and CI pipelines before production deployment.

## When to use

- Pre-release housekeeping across repos
- Reviewing Dockerfiles for image bloat or leaked artifacts
- Auditing npm packages for source code leakage
- Adding BuildKit cache mounts to speed up Docker builds

## Patterns

- [npm-package-hygiene.md](patterns/npm-package-hygiene.md) — Prevent source leaks and accidental publishes
- [docker-image-slimming.md](patterns/docker-image-slimming.md) — Exclude test/dev artifacts from production images
- [buildkit-cache-mounts.md](patterns/buildkit-cache-mounts.md) — Persist dependency caches across Docker builds
