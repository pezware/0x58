# Requirement Analysis Framework

A systematic approach to dissecting vague requirements into precise, actionable specifications.

## The Requirement Dissection Process

### Step 1: Identify Weasel Words

Common vague terms that require precision:

| Weasel Word | Question to Ask | Example Replacement |
|-------------|-----------------|---------------------|
| Fast | What is acceptable latency? | P95 < 200ms |
| Secure | Against what threats? | OWASP Top 10 mitigated |
| Scalable | To what load? | 10,000 concurrent users |
| Reliable | What uptime is acceptable? | 99.9% monthly |
| User-friendly | Measurable UX criteria? | <3 clicks to complete task |
| Robust | What failures to tolerate? | Handles 3 node failures |
| Efficient | What resource constraints? | <500MB memory per instance |
| Flexible | What variations supported? | JSON, XML, CSV formats |
| Modern | Specific technologies? | React 18, TypeScript 5 |
| Enterprise-grade | What features required? | SSO, audit logs, RBAC |

### Step 2: Ask the 5 Whys

For every requirement, trace to the root need:

**Example:**
1. "We need database caching" - Why?
2. "Queries are slow" - Why?
3. "We're hitting the DB for every request" - Why?
4. "There's no caching layer" - Why?
5. "We optimized for simplicity initially" - **Root cause: missing architecture component**

**Result:** The requirement is "Add caching to reduce DB load" not "make it faster"

### Step 3: Enumerate Edge Cases

For every happy path, identify:

- **Empty state**: What if there's no data?
- **Maximum state**: What if data exceeds limits?
- **Invalid input**: What if user provides garbage?
- **Concurrent access**: What if multiple users act simultaneously?
- **Failure state**: What if dependencies are unavailable?
- **Partial failure**: What if operation partially completes?

### Step 4: Define the Boundaries

Explicitly state what is IN and OUT of scope:

```markdown
## Scope

### In Scope
- User authentication via OAuth 2.0
- Session management with 24h timeout
- Password reset via email

### Out of Scope (Explicitly)
- Multi-factor authentication (Phase 2)
- Social login providers (not required)
- Remember me functionality (security policy)
- Account deletion (legal review pending)
```

## Requirement Quality Metrics

### The INVEST Criteria

Good user stories are:

- **I**ndependent - Can be developed without others
- **N**egotiable - Not a contract, can discuss
- **V**aluable - Delivers user/business value
- **E**stimable - Can estimate effort
- **S**mall - Fits in a sprint
- **T**estable - Has acceptance criteria

### The MoSCoW Method

Prioritize requirements:

| Category | Definition | Example |
|----------|------------|---------|
| **M**ust Have | Launch blockers | User login |
| **S**hould Have | Important, not critical | Password strength meter |
| **C**ould Have | Nice to have | Social login |
| **W**on't Have | Explicitly excluded | Biometric auth |

### Acceptance Criteria Checklist

Each criterion must be:

- [ ] **Atomic** - Tests one thing
- [ ] **Binary** - Pass/fail, no partial credit
- [ ] **Automatable** - Can write a test for it
- [ ] **Independent** - Doesn't depend on other criteria
- [ ] **Valuable** - Failing would matter to users

## Common Requirement Patterns

### CRUD Operations

When someone says "manage X", decompose into:

```markdown
### Data Entity: {X}

**Create:**
- Required fields: {list}
- Optional fields: {list}
- Validation rules: {list}
- Who can create: {roles}

**Read:**
- List view: {what columns, pagination}
- Detail view: {what fields}
- Search/filter: {what criteria}
- Who can view: {roles, ownership}

**Update:**
- Editable fields: {list}
- Non-editable fields: {list}
- Audit requirements: {what to track}
- Who can edit: {roles, ownership}

**Delete:**
- Soft delete or hard delete?
- Cascading effects: {what else is affected}
- Recovery options: {if any}
- Who can delete: {roles, ownership}
```

### Integration Requirements

When someone says "integrate with X":

```markdown
### Integration: {System X}

**Direction:**
- [ ] We call them (outbound)
- [ ] They call us (inbound)
- [ ] Bidirectional

**Data Flow:**
- What data do we send?
- What data do we receive?
- Transformation required?

**Protocol:**
- REST API / GraphQL / gRPC / Message Queue?
- Authentication method?
- Rate limits?

**Error Handling:**
- Retry strategy?
- Circuit breaker?
- Fallback behavior?

**SLA:**
- Expected latency?
- Availability requirements?
- Data freshness?
```

### Reporting Requirements

When someone says "we need reports":

```markdown
### Report: {Report Name}

**Purpose:**
- Who uses this report?
- What decisions does it inform?

**Content:**
- Data sources: {list}
- Metrics/aggregations: {list}
- Filters available: {list}
- Time ranges: {options}

**Delivery:**
- Real-time dashboard vs. batch export?
- Formats: PDF, CSV, interactive?
- Scheduling: on-demand, daily, weekly?

**Access Control:**
- Who can view?
- Row-level security needed?
- PII handling?
```

## Dealing with Stakeholders

### The "User" Trap

When requirements say "the user", ask:

- Which user persona?
- What is their role?
- What is their technical skill level?
- What is their frequency of use?
- What devices do they use?

### The "Simple" Request

When someone says "it's simple, just...":

1. List all the implicit requirements
2. Identify the hidden complexity
3. Propose the actual simple version
4. Let them choose complexity consciously

**Example:**
> "Just add a search box"

Implicit requirements:
- Full-text search vs. field search?
- Fuzzy matching?
- Search suggestions?
- Highlighting results?
- Ranking algorithm?
- Index building?
- Performance with large datasets?

Actual simple version:
> "Filter the list client-side by exact match on title field"

### The "Like Competitor X" Request

When someone says "make it like X":

1. Document exactly what X does (screenshots, flow diagrams)
2. Identify which specific behaviors they want
3. Note what X does that they don't want
4. Define our own acceptance criteria

### The "ASAP" Priority

When everything is urgent:

1. List all "urgent" items
2. Force-rank by asking: "If you could only have ONE, which?"
3. Repeat until stack-ranked
4. Map to sprints/phases based on capacity

## Requirement Anti-Patterns

### The Moving Target

**Symptom:** Requirements change faster than implementation

**Solution:**
- Freeze requirements per sprint
- Create change log for modifications
- Require cost assessment for changes

### The Gold Plate

**Symptom:** Adding features nobody asked for

**Solution:**
- Every feature needs a user story
- "Cool" is not a requirement
- Default to no, require justification for yes

### The Iceberg

**Symptom:** 10% visible, 90% hidden complexity

**Solution:**
- Decompose until no task is > 3 days
- Identify integration points explicitly
- Time-box research for unknowns

### The Premature Optimization

**Symptom:** "We might need it someday"

**Solution:**
- YAGNI: You Ain't Gonna Need It
- Build for today's requirements
- Design for extensibility (interfaces, not implementations)

## Requirement Documentation Checklist

Before marking a spec complete:

- [ ] All weasel words replaced with measurable criteria
- [ ] User personas identified for each story
- [ ] Edge cases enumerated
- [ ] Scope boundaries explicit
- [ ] Dependencies identified
- [ ] Non-functional requirements specified
- [ ] Acceptance criteria testable
- [ ] Out of scope documented
- [ ] Open questions resolved or owned
- [ ] Stakeholder sign-off obtained
