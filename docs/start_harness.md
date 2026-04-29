# AI Agent Development Harness

A practical framework for integrating AI coding agents (Claude Code, Codex, etc.) into professional workflows with mobile apps, GKE backends, Cloud Run, and mixed-stack repositories.

**Goal**: Catch AI mistakes early, reduce review noise, and provide at-a-glance visibility -- without adding workload.

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Architecture: Three-Layer Harness](#architecture-three-layer-harness)
3. [Layer 1: Role Isolation](#layer-1-role-isolation)
4. [Layer 2: Deterministic Hooks](#layer-2-deterministic-hooks)
5. [Layer 3: GitHub Status Lights](#layer-3-github-status-lights)
6. [The Implicit Spec Problem](#the-implicit-spec-problem)
7. [De-Hallucination Strategies](#de-hallucination-strategies)
8. [Structured Task Prompts](#structured-task-prompts)
9. [Review Without Slop](#review-without-slop)
10. [CLI Tools and Integrations](#cli-tools-and-integrations)
11. [Rollout Plan](#rollout-plan)
12. [Stack-Specific Guidance](#stack-specific-guidance)
13. [Tool Landscape](#tool-landscape)
14. [References](#references)

---

## The Problem

Five pain points, in order of leverage:

1. **Spec gap** -- agents don't know the implicit rules that live in your team's heads (no I/O in hot paths, don't expose ports, pin image versions, etc.)
2. **Wrong code** -- hallucinated APIs, missing edge cases, code that compiles but doesn't work
3. **Dangerous commands** -- blast radius when agents run `kubectl delete`, `terraform destroy`, or push to shared branches
4. **Review slop** -- AI reviews generate walls of text nobody reads, or miss real issues while flagging style nits
5. **No visibility** -- can't tell at a glance whether AI-touched PRs are safe to merge

These are layered: fixing #1 reduces #2, which reduces the burden on #4 and #5. And #3 is a safety net you need regardless.

---

## Architecture: Three-Layer Harness

```
 +---------------------------------------------+
 |  LAYER 3: PR-level (GitHub Actions)          |
 |  Status lights: pass/fail, not prose         |
 |                                              |
 |  +---------------------------------------+   |
 |  |  LAYER 2: Session-level (Hooks)       |   |
 |  |  Auto-format, block destructive cmds  |   |
 |  |                                       |   |
 |  |  +-------------------------------+    |   |
 |  |  |  LAYER 1: Role isolation      |    |   |
 |  |  |  Writer != Reviewer != Runner |    |   |
 |  |  +-------------------------------+    |   |
 |  +---------------------------------------+   |
 +---------------------------------------------+
```

Each layer is independent. Start with any one and add the others incrementally.

---

## Layer 1: Role Isolation

The principle: **the agent that writes code should not be the agent that reviews it.** Isolation is enforced at the configuration level, not by asking the agent to behave.

### Isolation Modes in Claude Code

| Pattern | Mechanism | Use Case |
|---------|-----------|----------|
| **Plan Mode** (`Ctrl+G` or `--permissionMode plan`) | Read-only tools only; no Write/Edit | Exploration, planning, code review |
| **Subagent with restricted tools** | `tools: Read, Grep, Glob` (no Write/Edit) | Code review, research, analysis |
| **acceptEdits mode** | Auto-accept file edits but prompt for Bash | Implementation with human oversight on commands |
| **Sandbox mode** (`/sandbox`) | OS-level filesystem and network isolation | Full autonomous operation within boundaries |
| **Git worktree isolation** (`isolation: "worktree"`) | Each agent gets its own working copy | Parallel implementation without file conflicts |

### Read-Only Reviewer Subagent

Create `.claude/agents/reviewer.md`:

```markdown
---
name: reviewer
description: Read-only code reviewer. Use immediately after modifying code.
tools: Read, Grep, Glob, Bash
model: inherit
---

You are a senior code reviewer. You CANNOT edit files.

When invoked:
1. Run git diff to see recent changes
2. Read .claude/include/constraints.md for project rules
3. Focus on modified files only

Review checklist:
- Compliance with constraints.md rules
- Correct error handling
- No exposed secrets or API keys
- Input validation at system boundaries
- Test coverage for new functionality
- Performance considerations (no N+1, no blocking I/O)

Organize output by priority:
- CRITICAL (must fix before merge)
- WARNING (should fix)
- INFO (consider improving)

Include specific file:line references and fix suggestions.
```

The reviewer literally cannot call Edit or Write. The tools are not available to it. This is what makes isolation enforceable rather than aspirational.

### Implementer Subagent

Create `.claude/agents/implementer.md`:

```markdown
---
name: implementer
description: Writes code based on task specs
tools: Read, Edit, Write, Bash, Grep, Glob
model: inherit
---

Before starting any implementation:
1. Read the task spec completely
2. Read .claude/include/constraints.md
3. Identify existing patterns in the codebase for similar features
4. Write tests first, then implement

After implementation:
1. Run the test suite
2. Run the linter
3. Verify all constraints.md rules are satisfied
```

### Writer/Reviewer Separation Pattern

The highest-confidence review pattern: implement in one Claude session (or subagent), review in a fresh session with no context from the writing phase.

Claude Code's own best practices documentation says it directly:

> "A fresh context improves code review since Claude won't be biased toward code it just wrote."

In practice:
- Session A: implement the feature
- Session B (fresh): `claude -p "Review the diff on this branch against main. Check against .claude/include/constraints.md. Report critical issues only."`

Or use the `context: fork` option in skills to get a clean context automatically.

### Security Reviewer Subagent

Create `.claude/agents/security-reviewer.md`:

```markdown
---
name: security-reviewer
description: Reviews code for security vulnerabilities
tools: Read, Grep, Glob, Bash
model: opus
---

Review code for:
- Injection vulnerabilities (SQL, command, XSS)
- Authentication and authorization bypasses
- Hardcoded secrets or API keys in code
- Exposed internal endpoints or ports
- Insecure data handling (PII logging, unencrypted storage)
- Missing input validation at system boundaries
- Container security (missing resource limits, running as root)
- Terraform/K8s misconfigurations (public buckets, wildcard CORS)

For each finding:
- Specific file:line reference
- Severity (critical/high/medium/low)
- Concrete fix suggestion
- CWE reference where applicable
```

---

## Layer 2: Deterministic Hooks

Hooks are shell scripts that run at specific lifecycle points in Claude Code. They are **deterministic** -- unlike asking the model to "double-check," a hook will always run. This is the enforcement loop.

### Hook Event Lifecycle

| Event | When it fires | Use for |
|-------|---------------|---------|
| `PreToolUse` | Before any tool call | Block dangerous commands, protect files |
| `PostToolUse` | After any tool call | Auto-format, run linters, background tests |
| `Stop` | Before Claude declares "done" | Verify tests pass, validate completeness |
| `TaskCompleted` | When an agent team member finishes a task | Quality gates for parallel work |
| `SessionStart` | When a session begins | Inject context, set up environment |
| `Notification` | When Claude needs user input | Desktop alerts |

### Hook Exit Codes

- `exit 0` -- allow the action to proceed
- `exit 1` -- show error to user only (not to Claude)
- `exit 2` -- **block the action** and feed stderr back to Claude as instructions

### Core Settings File

Create `.claude/settings.json` (commit to repo, shared by team):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-destructive.sh"
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/auto-lint.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/verify-tests.sh"
          }
        ]
      }
    ]
  }
}
```

### Hook: Block Destructive Commands

Create `.claude/hooks/block-destructive.sh`:

```bash
#!/bin/bash
# Blocks dangerous commands that could affect production or destroy data.
# Exit 2 = block and feed reason back to Claude.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Production-dangerous commands
if echo "$COMMAND" | grep -iE \
  '\b(kubectl delete|kubectl drain|terraform destroy|gcloud.*delete|DROP TABLE|DROP DATABASE|rm -rf /|TRUNCATE)\b' \
  > /dev/null; then
  echo "Blocked: destructive command requires manual execution. Run this yourself if intended." >&2
  exit 2
fi

# Force push protection
if echo "$COMMAND" | grep -iE 'git push.*--force|git push.*-f\b' > /dev/null; then
  echo "Blocked: force push is not allowed from agents. Use regular push." >&2
  exit 2
fi

# Production context protection
if echo "$COMMAND" | grep -iE 'kubectl.*(--context|--cluster).*prod' > /dev/null; then
  echo "Blocked: direct production cluster access from agents is not allowed." >&2
  exit 2
fi

exit 0
```

### Hook: Protect Sensitive Files

Create `.claude/hooks/protect-files.sh`:

```bash
#!/bin/bash
# Blocks edits to files that should not be modified by agents.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

PROTECTED_PATTERNS=(
  ".env"
  ".env.local"
  ".env.production"
  "credentials"
  "secrets"
  "package-lock.json"
  "yarn.lock"
  "Podfile.lock"
  "go.sum"
  ".git/"
  "*.pem"
  "*.key"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$pattern'. Edit this file manually." >&2
    exit 2
  fi
done

exit 0
```

### Hook: Auto-Lint by File Type

Create `.claude/hooks/auto-lint.sh`:

```bash
#!/bin/bash
# Runs the appropriate linter/formatter after every file edit.
# Works across mixed-stack repos.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  exit 0
fi

case "$FILE" in
  *.kt)
    ktlint -F "$FILE" 2>/dev/null
    ;;
  *.swift)
    swiftlint --fix --path "$FILE" 2>/dev/null
    ;;
  *.go)
    gofmt -w "$FILE" 2>/dev/null
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    npx prettier --write "$FILE" 2>/dev/null
    ;;
  *.tf)
    terraform fmt "$FILE" 2>/dev/null
    ;;
  *.py)
    black "$FILE" 2>/dev/null
    ;;
  *.yaml|*.yml)
    # yamllint is check-only, no auto-fix
    yamllint -d relaxed "$FILE" 2>/dev/null
    ;;
esac

exit 0
```

### Hook: Verify Tests Before Stopping

Create `.claude/hooks/verify-tests.sh`:

```bash
#!/bin/bash
# Runs the test suite before Claude can declare "done."
# Exit 2 sends Claude back to fix failing tests.

# Detect project type and run appropriate tests
if [ -f "go.mod" ]; then
  if ! go test ./... 2>&1; then
    echo "Tests failing. Fix all test failures before completing." >&2
    exit 2
  fi
elif [ -f "package.json" ]; then
  if ! npm test 2>&1; then
    echo "Tests failing. Fix all test failures before completing." >&2
    exit 2
  fi
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  if ! ./gradlew test 2>&1; then
    echo "Tests failing. Fix all test failures before completing." >&2
    exit 2
  fi
elif [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  if ! make test 2>&1; then
    echo "Tests failing. Fix all test failures before completing." >&2
    exit 2
  fi
fi

exit 0
```

### Hook: Stop Gate with LLM Verification

For an AI-powered stop gate that checks completeness (uses a fast model like Haiku):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Evaluate if Claude should stop: $ARGUMENTS. Check if: 1. All tasks from the original request are complete 2. Tests pass 3. No errors need addressing 4. constraints.md rules are satisfied. Respond with {\"ok\": true} or {\"ok\": false, \"reason\": \"...\"}",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

### Hook: Agent-Based Stop Gate

For a more thorough gate that can actually run commands and read files:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Verify the work is complete. Run the test suite. Check that all modified files comply with .claude/include/constraints.md. Report any issues. $ARGUMENTS",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### Hook: Diff Validation

Create `.claude/hooks/validate-diff.sh`:

```bash
#!/bin/bash
# Validates that edits follow conventions.
# Run as a PostToolUse hook on Edit|Write.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Block TODOs without issue numbers
if git diff -- "$FILE_PATH" 2>/dev/null | grep -E '^\+.*TODO|FIXME' | grep -vE '#[0-9]+'; then
  echo "Blocked: TODOs and FIXMEs must reference issue numbers (e.g., TODO #123)" >&2
  exit 2
fi

# Block console.log in production code (allow in test files)
if [[ "$FILE_PATH" != *"test"* && "$FILE_PATH" != *"spec"* ]]; then
  if git diff -- "$FILE_PATH" 2>/dev/null | grep -E '^\+.*console\.(log|debug)\(' > /dev/null; then
    echo "Blocked: console.log/debug found in production code. Use structured logging." >&2
    exit 2
  fi
fi

exit 0
```

### Make All Hooks Executable

```bash
chmod +x .claude/hooks/*.sh
```

---

## Layer 3: GitHub Status Lights

Instead of AI review comments that nobody reads, use GitHub Check Runs that show as green/red/yellow badges on the PR.

### What It Looks Like

```
PR #142: Add user profile API
  [green]  lint-and-test          (deterministic)
  [green]  type-check             (deterministic)
  [green]  security-scan          (AI, structured)
  [yellow] architecture-review    (AI, structured - 1 warning)
  [green]  test-coverage > 80%    (deterministic)
```

Each check is a separate GitHub Actions job. Click to expand details only if needed.

### GitHub Check Runs API

The foundation for status-light integration. A GitHub App can create pass/fail badges on PRs:

```
POST /repos/{owner}/{repo}/check-runs
```

Minimum payload:

```json
{
  "name": "ai-code-quality",
  "head_sha": "<commit-sha>",
  "status": "completed",
  "conclusion": "success",
  "output": {
    "title": "AI Review: No issues",
    "summary": "Score: 92/100. 0 critical, 1 warning, 2 suggestions."
  }
}
```

Conclusion values:
- `success` -- green checkmark
- `failure` -- red X
- `neutral` -- gray circle
- `action_required` -- yellow warning

**Important**: Only GitHub Apps can create check runs, not OAuth apps or personal tokens.

### AI Security Review Action

```yaml
# .github/workflows/ai-security-check.yml
name: AI Security Check

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  # Run deterministic checks first (fast, free)
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test       # or your test command
      - run: npm run lint    # or your lint command

  # AI security review (only if basics pass)
  security-review:
    runs-on: ubuntu-latest
    needs: lint-and-test
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Review ONLY the changed files in this PR for:
            1. Hardcoded secrets or API keys
            2. SQL/command injection risks
            3. Auth/authz bypasses
            4. Exposed internal endpoints or ports
            5. Missing input validation
            6. Container security issues (no resource limits, running as root)

            Output ONLY a JSON object:
            {"pass": true/false, "issues": ["one-line description per issue"]}

            If no issues found, output {"pass": true, "issues": []}
```

### Full Status-Light Action with Check Runs

```yaml
# .github/workflows/ai-quality-gate.yml
name: AI Quality Gate

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  ai-quality-check:
    runs-on: ubuntu-latest
    permissions:
      checks: write
      pull-requests: read
      contents: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Generate diff
        run: git diff origin/${{ github.base_ref }}...HEAD > /tmp/diff.txt

      - name: AI Analysis
        id: analysis
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          python3 << 'SCRIPT'
          import anthropic, json, os

          client = anthropic.Anthropic()
          diff = open("/tmp/diff.txt").read()[:50000]

          # Load project constraints if they exist
          constraints = ""
          try:
              constraints = open(".claude/include/constraints.md").read()
          except FileNotFoundError:
              pass

          response = client.messages.create(
              model="claude-sonnet-4-20250514",
              max_tokens=1000,
              messages=[{"role": "user", "content": f"""
                Analyze this code diff against the project constraints.
                Return JSON only, no other text:
                {{"score": 0-100, "conclusion": "success"|"failure"|"neutral",
                 "critical": 0, "warnings": 0, "suggestions": 0,
                 "summary": "one line summary"}}

                Scoring rules:
                - score < 50 or critical > 0 => conclusion "failure"
                - score 50-79 => conclusion "neutral"
                - score >= 80 => conclusion "success"

                Project constraints:
                {constraints}

                Diff:
                {diff}
              """}]
          )

          result = json.loads(response.content[0].text)
          with open(os.environ["GITHUB_OUTPUT"], "a") as f:
              for k, v in result.items():
                  f.write(f"{k}={v}\n")
          SCRIPT

      - name: Post Check Run
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.checks.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              name: 'AI Quality Gate',
              head_sha: context.payload.pull_request.head.sha,
              status: 'completed',
              conclusion: '${{ steps.analysis.outputs.conclusion }}',
              output: {
                title: 'Score: ${{ steps.analysis.outputs.score }}/100',
                summary: [
                  '${{ steps.analysis.outputs.summary }}',
                  '',
                  'Critical: ${{ steps.analysis.outputs.critical }}',
                  'Warnings: ${{ steps.analysis.outputs.warnings }}',
                  'Suggestions: ${{ steps.analysis.outputs.suggestions }}'
                ].join('\n')
              }
            });
```

### Multiple Signal Checks

For a multi-signal dashboard, create separate check runs in the same workflow:

```yaml
jobs:
  security-check:
    # ... outputs conclusion for security
  architecture-check:
    # ... outputs conclusion for architecture
  coverage-check:
    # ... outputs conclusion for test coverage
  complexity-check:
    # ... outputs conclusion for code complexity
```

Each appears as a separate status line on the PR. At a glance: all green = safe to merge. Any red = look closer.

### Branch Protection

Add the AI Quality Gate check as a required status check in your branch protection rules so PRs cannot merge until it passes.

---

## The Implicit Spec Problem

This is the highest-leverage intervention. The gap isn't "the agent can't code" -- it's "the agent doesn't know the rules that live in your team's heads."

### Repository Structure

```
repo-root/
  CLAUDE.md                    # repo-level: build/test/lint commands, stack info
  .claude/
    settings.json              # hooks (deterministic guards)
    settings.local.json        # personal preferences (gitignored)
    agents/                    # role-restricted subagents
      reviewer.md
      security-reviewer.md
      implementer.md
    skills/                    # reusable workflow templates
      task-template/SKILL.md
      review/SKILL.md
    hooks/                     # hook scripts
      block-destructive.sh
      protect-files.sh
      auto-lint.sh
      verify-tests.sh
      validate-diff.sh
    include/
      constraints.md           # THE KEY FILE: implicit rules made explicit
```

### The constraints.md File

This is where you codify the stuff that's "obvious" to your senior engineers but invisible to an agent:

```markdown
# Engineering Constraints

All code generated or modified by agents MUST comply with these rules.
Violations will be caught by automated hooks and CI checks.

## Performance
- No synchronous I/O in request handlers. Use async patterns everywhere.
- No N+1 queries. Batch or preload related data.
- No unbounded list fetches. Always paginate with sensible defaults.
- No blocking the main thread (mobile). Heavy work goes to background threads/coroutines.
- No polling when push/streaming is available.

## Security
- No ports exposed unless explicitly requested in the task spec.
- No hardcoded secrets. Use Secret Manager / environment variable references.
- No wildcard CORS. Specify exact allowed origins.
- No raw SQL. Use parameterized queries or ORM.
- All user input must be validated at system boundaries.
- No PII in log output.

## Infrastructure (GKE / Cloud Run)
- No `latest` tags in container images. Pin to specific versions or digests.
- No LoadBalancer services. Use Ingress through GKE Gateway.
- All pods must have resource requests and limits.
- All pods must have security contexts (non-root, read-only filesystem where possible).
- No ClusterIP services exposed externally without auth.
- Terraform: never destroy+recreate. Use moved blocks for resource renames.

## Mobile (Android / iOS)
- No raw HTTP calls. Use the existing API client layer.
- No blocking main thread. Use coroutines (Kotlin) or async/await (Swift).
- No hardcoded strings for user-facing text. Use string resources / localization.
- Support offline-first patterns where applicable.
- Respect platform lifecycle (Activity/Fragment lifecycle, UIViewController lifecycle).

## Code Organization
- Follow existing project structure and naming conventions.
- No new dependencies without explicit justification in the task spec.
- No changes to CI/CD configuration unless explicitly requested.
- Lock files (package-lock.json, go.sum, Podfile.lock) are never edited by agents.

## Testing
- All new functionality must have tests.
- Tests must be deterministic (no flaky tests, no time-dependent assertions).
- Test behavior, not implementation details.
- Use existing test utilities and helpers.
```

### CLAUDE.md Template

Each repo gets a `CLAUDE.md` at the root:

```markdown
# Project: [repo-name]

## Stack
- Language: [Go/TypeScript/Kotlin/Swift/etc.]
- Framework: [Echo/Express/Jetpack Compose/SwiftUI/etc.]
- Database: [PostgreSQL/Firestore/etc.]
- Infrastructure: [GKE/Cloud Run/etc.]

## Build
- Build: `[make build / npm run build / ./gradlew build]`
- Test: `[make test / npm test / ./gradlew test]`
- Lint: `[golangci-lint run / npm run lint / ktlint]`
- Format: `[gofmt -w . / npx prettier --write . / ktlint -F]`

## Before Implementing Any Task
1. Read `.claude/include/constraints.md` -- all code must comply.
2. Study 2-3 similar features in the codebase for patterns.
3. Write tests first (red), then implement (green), then refactor.

## Project-Specific Rules
- [Add repo-specific rules here, e.g., "API responses use snake_case JSON keys"]
- [E.g., "All database queries go through the repository layer, never direct SQL in handlers"]
```

### Maintaining constraints.md

Treat it like any other documentation:
- When someone catches a new "obvious" thing the agent missed, add a rule
- Review quarterly to remove outdated rules
- Keep it under 100 lines -- if it gets longer, the signal gets diluted

---

## De-Hallucination Strategies

Ranked by effectiveness:

### Tier 1: Tests (Highest Confidence)

Write tests first, then let the AI implement. Red-green-refactor works exceptionally well with agents because the agent has concrete pass/fail criteria.

Use `Stop` hooks to enforce "tests must pass before done."

```
Human writes test -> Agent sees test fail -> Agent implements -> Test passes -> Done
```

This is the single most effective de-hallucination technique. The agent cannot hallucinate its way past a failing test.

### Tier 2: Deterministic Tools

Linters, type checkers, formatters run automatically via hooks. These catch a large class of hallucinated code:
- Wrong types (TypeScript strict, mypy, Go compiler)
- Syntax errors
- Style violations
- Import errors (missing modules)

These are free to run and always correct. Put them in PostToolUse hooks.

### Tier 3: Context Grounding

Keep prompts small and scoped. The three-phase approach (widely cited, originally from Harper Reed):

1. **Spec**: generate a developer-ready specification (spec.md)
2. **Plan**: break into small, iterative chunks (prompt_plan.md + todo.md)
3. **Execute**: implement prompts sequentially, one at a time

Each step grounds the next. The spec prevents hallucinated requirements, the plan prevents scope creep, and small sequential prompts prevent "going over your skis."

**Context packaging**: Tools like [Repomix](https://github.com/yamadashy/repomix) bundle codebases into a single file, preventing context loss during long iterations.

**CLAUDE.md grounding**: Putting build commands, conventions, and constraints.md in the project gives the agent something concrete to reference instead of guessing.

### Tier 4: Fresh-Context Review

A second AI pass with no memory of writing the code. This is genuinely useful but should come AFTER tiers 1-3.

Options:
- Separate Claude Code session
- Read-only subagent (see Layer 1)
- Skill with `context: fork`
- Claude Code GitHub Action (inherently fresh context)

### What Does NOT Work

- Asking the same AI to "double-check" in the same context (confirmation bias)
- "Confidence scores" as a standalone technique -- models are poorly calibrated about their own certainty
- Verbose AI reviews as a primary safety net (too much noise, real issues get buried)

---

## Structured Task Prompts

The "not too much, not too little" problem: agents are eager to please and will add caching, logging, metrics, error reporting, etc. unless told not to.

### Task Template

Instead of: *"Add user profile endpoint"*

Use:

```markdown
## Task
Add GET /api/v1/users/{id}/profile endpoint

## Must Include
- Return user profile with name, avatar_url, created_at
- 404 if user not found
- Auth required (use existing auth middleware)
- Unit test for happy path and 404 case

## Must NOT Include
- No new database migrations
- No new dependencies
- No changes to existing endpoints
- No caching layer (separate task)
- No metrics/observability changes

## Constraints
- Follow .claude/include/constraints.md
- Match existing handler patterns in handlers/

## Done When
- All tests pass (including new ones)
- Linter passes
- Endpoint responds correctly with curl test
```

The "Must NOT Include" section prevents scope creep. **Explicit exclusions are more effective than implicit expectations.**

### Task Template Skill

Create `.claude/skills/task-template/SKILL.md`:

```markdown
---
name: task-template
description: Generate a structured task prompt with scope boundaries
---

Help the user write a structured task prompt with these sections:

1. **Task** -- what to build (one sentence)
2. **Must Include** -- explicit deliverables, each testable
3. **Must NOT Include** -- scope boundaries, prevent gold-plating
4. **Constraints** -- reference .claude/include/constraints.md + task-specific rules
5. **Done When** -- concrete verification criteria

Ask the user clarifying questions to fill each section.
Bias toward smaller scope rather than larger.
```

---

## Review Without Slop

### The Problem with AI Reviews

Most AI code review tools produce walls of text: style suggestions, obvious observations, restating what the code does, and generic advice. This adds workload instead of reducing it.

### The Fix: Domain-Specific, Structured, Brief

Create `.claude/skills/review/SKILL.md`:

```markdown
---
name: review
description: Review code changes against team standards
context: fork
agent: Explore
---

Review the git diff of the current branch against main.

Check ONLY for:
1. Violations of .claude/include/constraints.md
2. Security issues (injection, auth bypass, exposed secrets)
3. Bugs (null pointer, race condition, resource leak)
4. Missing error handling at system boundaries

Do NOT comment on:
- Code style (handled by linters)
- Naming conventions (handled by linters)
- Documentation gaps (unless public API)
- "Consider" suggestions or "nice to have" improvements

Output format:
- If no issues: "LGTM - no critical issues found"
- If issues found: numbered list, one line each, with file:line reference
```

The `context: fork` ensures fresh context. The `agent: Explore` means read-only. The explicit "Do NOT comment on" section eliminates the slop.

### Invoking from GitHub Actions

```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    prompt: "/review"
    claude_args: "--max-turns 5"
```

The `--max-turns 5` cap prevents runaway review sessions.

### Multi-Agent Parallel Review

Instead of one reviewer that tries to cover everything, spawn specialized reviewers:

```
Create an agent team to review this PR. Spawn three reviewers:
- One focused on security implications
- One checking for constraint violations
- One validating test coverage
Have them each review and report findings.
```

Each produces focused, domain-specific findings. Higher signal than a single pass.

---

## CLI Tools and Integrations

### Claude Code Non-Interactive Mode

```bash
# Structured output for CI scripts
claude -p "List all API endpoints" --output-format json

# Streaming for real-time processing
claude -p "Analyze this log file" --output-format stream-json

# Scoped tool access
claude -p "Review this diff for security issues" \
  --allowedTools "Read,Grep,Glob,Bash(git diff *)"

# Pre-commit check
claude -p "Review staged changes for security issues. Return exit code 1 if blocking." \
  --output-format json
```

### Claude Code GitHub Action

[`anthropics/claude-code-action@v1`](https://github.com/anthropics/claude-code-action) -- GA since Aug 2025, 6k+ stars.

Key capabilities:
- `@claude` mentions in PRs and issues trigger automated responses
- Supports Anthropic API, AWS Bedrock, Google Vertex AI
- `/install-github-app` command in Claude Code CLI sets it up
- Skills can be invoked from Actions
- Structured JSON outputs feed into downstream CI steps

### Repomix

[Repomix](https://github.com/yamadashy/repomix) bundles codebases into a single file for context packaging. Prevents context loss and hallucination during long iterations on established codebases.

```bash
npx repomix
# Generates output.txt with your codebase
```

### Useful Hook Patterns Reference

| Hook Event | Matcher | Purpose | Script |
|------------|---------|---------|--------|
| `PostToolUse` | `Edit\|Write` | Auto-format after every edit | `auto-lint.sh` |
| `PreToolUse` | `Bash` | Block destructive commands | `block-destructive.sh` |
| `PreToolUse` | `Edit\|Write` | Protect sensitive files | `protect-files.sh` |
| `PostToolUse` | `Edit\|Write` | Validate diff conventions | `validate-diff.sh` |
| `Stop` | (all) | Verify tests pass | `verify-tests.sh` |
| `Stop` | (all) | LLM completeness check | prompt hook (see above) |
| `PostToolUse` | `Write\|Edit` | Background test runner | async command hook |
| `SessionStart` | (all) | Inject cluster context | `echo "Context: $(kubectl config current-context)"` |
| `Notification` | (all) | Desktop alerts | `osascript -e 'display notification ...'` |

---

## Rollout Plan

Each week adds value independently. Skip or reorder based on what hurts most.

### Week 1-2: Foundation (constraints.md + CLAUDE.md)

**What**: Write down 10-15 implicit rules in `constraints.md`. Add `CLAUDE.md` with build/test/lint commands to each repo.

**Why**: This alone cuts hallucination and scope creep significantly. Zero infrastructure needed.

**Effort**: 1-2 hours per repo.

**Files to create**:
- `CLAUDE.md` (repo root)
- `.claude/include/constraints.md`

### Week 3-4: Safety Hooks

**What**: Add three hooks to `.claude/settings.json` -- block destructive commands, auto-lint, verify tests on stop.

**Why**: Deterministic safety net. Catches dangerous commands and formatting issues automatically.

**Effort**: 2-3 hours total, then copy across repos.

**Files to create**:
- `.claude/settings.json`
- `.claude/hooks/block-destructive.sh`
- `.claude/hooks/protect-files.sh`
- `.claude/hooks/auto-lint.sh`
- `.claude/hooks/verify-tests.sh`

### Week 5-6: Status-Light CI

**What**: One GitHub Action workflow per repo with AI security review as a pass/fail check run.

**Why**: At-a-glance visibility. Green = safe, red = look closer. No comment walls.

**Effort**: 3-4 hours for the first repo, 30 minutes for each subsequent repo.

**Files to create**:
- `.github/workflows/ai-quality-gate.yml`

### Week 7-8: Structured Tasks + Review Skill

**What**: Roll out task-template skill and focused review skill. Train team to write "Must NOT include" sections.

**Why**: Addresses the spec gap. Prevents scope creep and gold-plating.

**Effort**: 1-2 hours setup, then ongoing habit formation.

**Files to create**:
- `.claude/skills/task-template/SKILL.md`
- `.claude/skills/review/SKILL.md`

### Week 9-10: Fresh-Context Reviewer

**What**: Add read-only reviewer subagent. One Claude writes, another reviews.

**Why**: Catches constraint violations and architectural issues the writer missed.

**Effort**: 1 hour setup.

**Files to create**:
- `.claude/agents/reviewer.md`
- `.claude/agents/security-reviewer.md`

### What NOT to Do Yet

- Don't try agent teams or multi-agent orchestration until the basics are solid
- Don't try to get AI to write PRs or do automated fixes
- Don't add AI to the path to production -- keep it advisory
- Don't add more than one AI check to CI initially (start with security only)

---

## Stack-Specific Guidance

### Mobile Apps (Android / iOS)

- Use `PostToolUse` hooks to run platform-specific linters (ktlint, SwiftLint) after every edit
- Create skills for common workflows: `/build-android`, `/build-ios`, `/run-tests`
- Use git worktree isolation when running parallel agents to avoid Xcode/Gradle lock conflicts
- Add mobile-specific rules to constraints.md (no main thread blocking, use string resources, respect lifecycle)

### GKE Backends

- `PreToolUse` hook blocks `kubectl delete`, `terraform destroy` in production contexts
- Security reviewer subagent checks Kubernetes manifests (resource limits, security contexts, RBAC)
- `SessionStart` hook injects current cluster context: `echo "Current context: $(kubectl config current-context)"`
- Create skills for common operations: `/deploy-staging`, `/check-pods`, `/rollback`
- Add GKE-specific rules to constraints.md (no LoadBalancer, pin image versions, use moved blocks)

### Cloud Run

- Add rules about concurrency settings, max instances, and cold start considerations to constraints.md
- Security reviewer checks for exposed ports, missing auth, and overly permissive IAM
- CI checks validate Dockerfile best practices (multi-stage builds, non-root user)

### Terraform / Infrastructure

- `PreToolUse` hook blocks `terraform destroy` and `terraform apply` without `-var-file`
- Add rules about state management, moved blocks, and resource naming
- Review hook specifically checks for: public buckets, wildcard IAM, missing encryption

### GitHub Workflow

- Commit `.claude/settings.json`, `.claude/skills/`, and `.claude/agents/` to repos so the whole team benefits
- Use `.claude/settings.local.json` (gitignored) for personal preferences
- The Claude Code GitHub Action with `/review` skill gives consistent PR review without comment flooding

---

## Tool Landscape

### Comparison (as of early 2026)

| Tool | Type | Concise Signals? | Status Checks? | Best For |
|------|------|-------------------|----------------|----------|
| **Claude Code hooks** | Local tooling | DIY (full control) | N/A (local) | Deterministic safety, auto-formatting |
| **Claude Code GitHub Action** | CI integration | Configurable | Via Check Runs API | PR review, automated fixes |
| **Greptile** | SaaS platform | Yes (scores, severity) | Unclear | At-a-glance confidence scores |
| **Qodo Merge** | SaaS/OSS | Partial (severity priority) | No | Requirement validation |
| **CodeRabbit** | SaaS | Partial (summaries) | No | Comprehensive review with diagrams |
| **Sourcery AI** | GitHub App | No (verbose) | No | Narrative feedback |
| **GitHub Copilot Agents** | IDE + CI | Evolving | Yes (native) | GitHub-native workflows |
| **Cursor Bugbot** | IDE + Cloud | Yes (fixes, not comments) | No | Auto-fixing issues in PRs |

### Recommendations

- **Start with Claude Code hooks + GitHub Action** -- most control, CLI-first, composes with your existing workflow
- **Evaluate Greptile** if you want off-the-shelf confidence scores and don't want to build the CI pipeline yourself
- **Skip verbose review tools** (Sourcery, generic AI reviewers) -- they create the slop problem you're trying to avoid
- **Watch GitHub Copilot Agents** -- their "Agentic Workflows" (technical preview, Feb 2026) may become the native platform solution

---

## Key Principles

1. **Deterministic before probabilistic.** Tests, linters, type checkers catch more bugs more reliably than AI review. AI review adds value on top of that foundation.

2. **Configuration-level isolation, not prompt-level requests.** A subagent with `tools: Read, Grep, Glob` literally cannot edit files. "Please don't edit files" can be ignored.

3. **Explicit exclusions beat implicit expectations.** "Must NOT include" in task specs prevents more scope creep than "be minimal."

4. **Fresh context for review.** Never review code in the same context that wrote it. Use subagents, forked skills, or separate sessions.

5. **Status lights, not prose.** Green/red/yellow badges are glanceable. Comment walls are not.

6. **Make implicit knowledge machine-readable.** The constraints.md file is the bridge between what your team knows and what agents can enforce. Once it exists, hooks and CI checks have something concrete to validate against.

7. **Start with what hurts.** Each piece works independently. Don't build the full harness at once -- pick the biggest pain point and address it first.

---

## References

- [Claude Code Hooks Documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Claude Code Sub-Agents Documentation](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Claude Code GitHub Action](https://github.com/anthropics/claude-code-action)
- [Claude Code Best Practices](https://docs.anthropic.com/en/docs/claude-code/best-practices)
- [GitHub Check Runs API](https://docs.github.com/en/rest/checks/runs)
- [Harper Reed's LLM Codegen Workflow](https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/)
- [Simon Willison on AI-Assisted Programming](https://simonwillison.net/tags/ai-assisted-programming/)
- [Cursor Bugbot Autofix](https://www.cursor.com/blog)
- [Greptile AI Code Review](https://www.greptile.com/)
- [Repomix](https://github.com/yamadashy/repomix)
