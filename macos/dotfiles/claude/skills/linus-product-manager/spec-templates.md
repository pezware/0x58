# Specification Templates

Templates for consistent, high-quality specifications following spec-kit methodology.

## User Story Template

```markdown
### US-{NUMBER}: {Short Title}

As a {role/persona}
I want to {action/capability}
So that {business value/outcome}

**Context:**
{Background information and current state}

**Acceptance Criteria:**
- [ ] {Testable criterion 1 with specific threshold}
- [ ] {Testable criterion 2 with specific threshold}
- [ ] {Testable criterion 3 with specific threshold}

**Out of Scope:**
- {Explicit exclusion 1}
- {Explicit exclusion 2}

**Dependencies:**
- {Prerequisite 1}
- {Prerequisite 2}
```

## Feature Specification Template

```markdown
# Feature: {Feature Name}

## Problem Statement

{2-3 sentences describing the problem this feature solves. Focus on WHO has
the problem, WHAT the problem is, and WHY it matters.}

## Success Metrics

| Metric | Current | Target | Measurement Method |
|--------|---------|--------|-------------------|
| {Metric 1} | {baseline} | {goal} | {how to measure} |

## User Stories

{Include 2-5 user stories using the template above}

## Non-Functional Requirements

### Performance
- Response time: P95 < {X}ms
- Throughput: {X} requests/second
- Availability: {X}% uptime

### Security
- Authentication: {method}
- Authorization: {model}
- Data protection: {requirements}

### Scalability
- Initial load: {baseline}
- Growth projection: {expected growth}
- Scale limit: {maximum supported}

## Constraints

| Constraint | Rationale |
|------------|-----------|
| {Technical constraint} | {Why this constraint exists} |
| {Business constraint} | {Why this constraint exists} |

## Open Questions

- [ ] {Question 1} - Owner: {name}
- [ ] {Question 2} - Owner: {name}

## Appendix

### Glossary
- **{Term}**: {Definition}

### References
- {Link to related docs}
```

## Technical Plan Template

```markdown
# Technical Plan: {Feature Name}

## Architecture Overview

{High-level description of the approach. Include diagram if helpful.}

```
[ASCII or Mermaid diagram]
```

## Technology Decisions

| Decision | Choice | Alternatives Considered | Rationale |
|----------|--------|------------------------|-----------|
| {Decision} | {Choice} | {Alt 1, Alt 2} | {Why this choice} |

## Component Design

### Component 1: {Name}

**Purpose:** {What this component does}

**Interfaces:**
- Input: {what it receives}
- Output: {what it produces}

**Implementation Notes:**
- {Key implementation detail}

### Component 2: {Name}
{...}

## Data Model

### Entity: {Name}
| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| {field} | {type} | {constraints} | {description} |

## API Contracts

### Endpoint: {METHOD /path}

**Request:**
```json
{
  "field": "type"
}
```

**Response:**
```json
{
  "field": "type"
}
```

**Error Codes:**
| Code | Meaning | Resolution |
|------|---------|------------|
| {code} | {meaning} | {how to fix} |

## Dependencies

### External Dependencies
- {Dependency}: {Version} - {Why needed}

### Internal Dependencies
- {Component}: {Interface} - {How used}

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| {Risk} | High/Med/Low | High/Med/Low | {How to mitigate} |

## Testing Strategy

### Unit Tests
- {What to test at unit level}

### Integration Tests
- {What to test at integration level}

### E2E Tests
- {Critical user flows to test}

## Rollout Plan

### Phase 1: {Name}
- Target: {environment}
- Duration: {time}
- Success criteria: {metrics}
- Rollback trigger: {conditions}

### Phase 2: {Name}
{...}

## Monitoring & Alerting

| Metric | Threshold | Alert Action |
|--------|-----------|--------------|
| {metric} | {threshold} | {what to do} |
```

## Task Breakdown Template

```markdown
# Implementation Tasks: {Feature Name}

## Overview

Total tasks: {N}
Estimated effort: {time}
Parallelizable: {N} tasks

## Task Dependency Graph

```
[1.1] ─┬─→ [2.1] ─→ [3.1]
[1.2] ─┘           ↓
                [3.2] ─→ [4.1]
```

## Checkpoint 1: {Name}

### Task 1.1: {Title}
- **File(s):** {path/to/file}
- **Creates/Modifies:** {resource/code}
- **Depends on:** {dependencies or "None"}
- **Parallelizable:** [P] or [-]
- **Estimated effort:** {time}

**Description:**
{What this task accomplishes}

**Test criteria:**
- [ ] {How to verify this task is complete}

### Task 1.2: {Title}
{...}

## Checkpoint 2: {Name}
{...}

## Checkpoint: Validation (Final)

### Task N.1: Verify acceptance criteria
- Run acceptance test suite
- Verify all criteria from spec.md

### Task N.2: Documentation update
- Update relevant docs
- Add runbook entries if needed

### Task N.3: Stakeholder demo
- Demo to stakeholders
- Collect feedback
- Create follow-up issues if needed
```

## Clarification Template

```markdown
# Clarifications: {Feature Name}

## Process

For each unclear requirement:
1. State what is unclear
2. List possible interpretations
3. Document the decision
4. Update the spec

## Clarifications

### CL-1: {Topic}

**Question:**
{What is unclear?}

**Interpretations:**
1. {Interpretation A} - Implication: {what this means}
2. {Interpretation B} - Implication: {what this means}

**Decision:**
{Chosen interpretation and rationale}

**Spec Update:**
- Section: {which section}
- Change: {what changed}

---

### CL-2: {Topic}
{...}

## Assumptions Log

| Assumption | Made By | Date | Validated |
|------------|---------|------|-----------|
| {assumption} | {name} | {date} | Yes/No/Pending |
```

## Checklist Template

```markdown
# Quality Checklist: {Feature Name}

## Pre-Implementation

- [ ] Spec reviewed by tech lead
- [ ] Dependencies available
- [ ] Test environment ready
- [ ] Monitoring plan defined

## During Implementation

### Per Task
- [ ] Tests written before implementation
- [ ] Code compiles without warnings
- [ ] Linting passes
- [ ] Security scan clean

### Per Checkpoint
- [ ] All checkpoint tasks complete
- [ ] Integration tests pass
- [ ] Checkpoint demo completed

## Pre-Release

### Code Quality
- [ ] All tests pass
- [ ] Code coverage >= {threshold}%
- [ ] No critical security findings
- [ ] Performance benchmarks met

### Documentation
- [ ] API documentation updated
- [ ] Runbook updated
- [ ] Architecture diagrams current

### Operational Readiness
- [ ] Monitoring dashboards configured
- [ ] Alerts configured
- [ ] Rollback plan documented
- [ ] On-call briefed

## Post-Release

- [ ] Smoke tests pass in production
- [ ] Metrics within expected range
- [ ] No error rate spike
- [ ] Stakeholders notified
```

## Constitution Template

```markdown
# Project Constitution: {Project Name}

## Purpose

{Why this project exists - 2-3 sentences}

## Principles

### P1: {Principle Name}
{Description of the principle and why it matters}

**Violations look like:**
- {Example of violating this principle}

**Compliance looks like:**
- {Example of following this principle}

### P2: {Principle Name}
{...}

## Technology Constraints

| Domain | Constraint | Rationale |
|--------|------------|-----------|
| Language | {constraint} | {why} |
| Framework | {constraint} | {why} |
| Infrastructure | {constraint} | {why} |

## Quality Gates

### Must Pass
- [ ] {Gate 1}
- [ ] {Gate 2}

### Should Pass
- [ ] {Gate 1}
- [ ] {Gate 2}

## Code Standards

### Naming Conventions
- {Convention 1}
- {Convention 2}

### File Organization
- {Convention 1}
- {Convention 2}

## Review Requirements

| Change Type | Reviewers Required | Approval Needed |
|-------------|-------------------|-----------------|
| {type} | {number} | {roles} |

## Exceptions Process

To request an exception to these principles:
1. {Step 1}
2. {Step 2}
3. {Step 3}
```
