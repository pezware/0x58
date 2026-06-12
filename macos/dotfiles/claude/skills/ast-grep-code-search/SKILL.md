---
name: ast-grep-code-search
description: Use ast-grep for structural code search and replace operations based on Abstract Syntax Trees. Performs precise, language-aware refactoring that understands code structure beyond simple text patterns.
---

# AST-Grep Code Search and Replace

This skill enables precise, structure-aware code search and refactoring using ast-grep, a tool that operates on Abstract Syntax Trees (AST) rather than text patterns.

## When to Use AST-Grep vs Other Tools

### Use AST-Grep When:
- **Structural matching needed**: Find code patterns based on syntax structure, not just text
- **Language-aware refactoring**: Rename functions, migrate APIs, transform patterns
- **Avoiding false positives**: Text-based grep would match comments, strings, or wrong contexts
- **Complex transformations**: Need to capture and reuse code fragments in replacements
- **Multi-language projects**: Same concepts across TypeScript, Python, Rust, etc.

### Use Regular Grep When:
- Simple string search across any file type
- Searching non-code files (markdown, configs, logs)
- Performance is critical for large searches
- Pattern is truly text-based (URLs, IDs, simple strings)

### Examples:

**Use AST-Grep:**
```bash
# Find optional chaining opportunities (structural)
ast-grep -p '$PROP && $PROP()' -l typescript

# Find all function calls with specific pattern (structural)
ast-grep -p 'console.log($$$)' -l javascript

# Find React hooks with dependencies (structural)
ast-grep -p 'useEffect($$$, [$DEPS])' -l typescript
```

**Use Regular Grep:**
```bash
# Find TODO comments (text-based)
grep -r "TODO:" .

# Find file imports by path (text-based)
grep -r "from '@/components" .

# Find configuration values (text-based)
grep -r "API_KEY" .
```

## Core Concepts

### Abstract Syntax Trees (AST)
- Code is parsed into a tree structure representing its syntax
- ast-grep matches patterns against this tree, not against raw text
- This allows matching code structure regardless of formatting, whitespace, or comments

### Meta Variables
Meta variables are wildcards that capture AST nodes:

1. **Single Node: `$VAR`**
   - Matches exactly one AST node
   - Name must be uppercase letters, digits, or underscores
   - Examples: `$A`, `$PROP`, `$VALUE`, `$ARG1`

2. **Multiple Nodes: `$$$`**
   - Matches zero or more consecutive AST nodes
   - Use for variable-length sequences (function args, statements, array elements)
   - Can optionally name it: `$$$ARGS`, `$$$BODY`

3. **Anonymous Variables: `$_VAR`**
   - Matches but doesn't capture (like non-capturing groups in regex)
   - Use when you need to match structure but don't need the value

### Pattern Writing Rules

1. **Patterns must be valid, parseable code**
   ```typescript
   // Good: Valid TypeScript
   ast-grep -p 'function $NAME($$$PARAMS) { $$$BODY }'

   // Bad: Invalid syntax
   ast-grep -p 'function $NAME($$$)'  // Missing function body!
   ```

2. **Patterns match structure, not text**
   ```typescript
   // Pattern: console.log($MSG)
   // Matches all of these:
   console.log("hello")
   console.log(x + y)
   console.log(
     someVariable
   )
   // But NOT: console.error($MSG) - different function!
   ```

3. **Use language-specific syntax**
   ```bash
   # Python
   ast-grep -p 'def $FUNC($$$): $$$' -l python

   # Rust
   ast-grep -p 'fn $FUNC($$$) { $$$ }' -l rust

   # TypeScript
   ast-grep -p 'function $FUNC($$$) { $$$ }' -l typescript
   ```

## CLI Usage

### Basic Search

```bash
# Search for pattern in current directory
ast-grep --pattern '$PATTERN' --lang LANGUAGE

# Short form (recommended)
ast-grep -p '$PATTERN' -l LANGUAGE

# Can also use 'sg' alias
sg -p '$PATTERN' -l typescript

# Search specific files/directories
ast-grep -p '$PATTERN' -l python src/
```

### Language Options

Supported languages (use with `-l` or `--lang`):
- `typescript`, `javascript`, `tsx`, `jsx`
- `python`, `rust`, `go`, `java`, `c`, `cpp`
- `html`, `css`, `json`, `yaml`
- Many more via tree-sitter parsers

### Search Examples

```bash
# Find all console.log statements
ast-grep -p 'console.log($$$)' -l typescript

# Find functions with specific name
ast-grep -p 'function handleSubmit($$$) { $$$ }' -l javascript

# Find class methods
ast-grep -p 'class $CLASS { $METHOD($$$) { $$$ } }' -l typescript

# Find specific React hooks
ast-grep -p 'useState($INIT)' -l typescript

# Find if statements with specific condition
ast-grep -p 'if ($A && $A()) { $$$ }' -l javascript
```

### Output Control

```bash
# Show only file names (like grep -l)
ast-grep -p '$PATTERN' -l typescript --json | jq -r '.file'

# Show with context lines
ast-grep -p '$PATTERN' -l typescript -A 3 -B 3

# Count matches
ast-grep -p '$PATTERN' -l typescript --json | jq 'length'

# Output as JSON for processing
ast-grep -p '$PATTERN' -l typescript --json
```

## Code Rewriting

### Simple CLI Rewrites

```bash
# Basic rewrite syntax
ast-grep -p '$PATTERN' --rewrite '$FIX' -l LANGUAGE

# Interactive mode (confirm each change)
ast-grep -p '$PATTERN' --rewrite '$FIX' -l LANGUAGE --interactive

# Example: Convert to optional chaining
ast-grep \
  -p '$PROP && $PROP()' \
  --rewrite '$PROP?.()' \
  -l typescript \
  --interactive

# Example: Use logical assignment
ast-grep \
  -p '$A = $A || $B' \
  --rewrite '$A ||= $B' \
  -l javascript

# Example: Modernize React imports
ast-grep \
  -p "import React from 'react'" \
  --rewrite "import { useState, useEffect } from 'react'" \
  -l typescript
```

### Meta Variable Reuse in Rewrites

Meta variables captured in the pattern can be reused in the rewrite:

```bash
# Capture $FUNC and $ARGS, reuse in fix
ast-grep \
  -p 'await fetch($URL).then($FUNC)' \
  --rewrite 'await fetch($URL).then(async (res) => $FUNC(await res.json()))' \
  -l typescript

# Swap arguments
ast-grep \
  -p 'assertEquals($ACTUAL, $EXPECTED)' \
  --rewrite 'assertEquals($EXPECTED, $ACTUAL)' \
  -l typescript

# Rename function keeping arguments
ast-grep \
  -p 'oldFunction($$$ARGS)' \
  --rewrite 'newFunction($$$ARGS)' \
  -l python
```

## YAML Rule Configuration

For complex searches and rewrites, use YAML rule files:

### Basic Rule Structure

```yaml
# rule.yml
id: unique-rule-id
language: typescript
rule:
  pattern: $PATTERN
fix: $FIX_PATTERN
message: Description of what this rule does
```

### Atomic Rules

```yaml
# Pattern matching
rule:
  pattern: console.log($$$)

# Kind matching (specific AST node types)
rule:
  kind: function_declaration

# Regex matching
rule:
  regex: ^test_.*

# All of these (AND logic)
rule:
  all:
    - pattern: function $NAME($$$) { $$$ }
    - regex: ^handle
```

### Relational Rules

```yaml
# Find nodes inside another node
rule:
  pattern: $AWAIT
  inside:
    pattern: Promise.all($$$)
    stopBy: end

# Find nodes that have a child
rule:
  pattern: Promise.all($ARGS)
  has:
    pattern: await $_

# Find nodes that follow another
rule:
  pattern: $STMT
  follows:
    pattern: console.log($$$)

# Find nodes that precede another
rule:
  pattern: $STMT
  precedes:
    pattern: return $VAL
```

### Composite Rules

```yaml
# All conditions must match (AND)
rule:
  all:
    - pattern: function $NAME($$$) { $$$ }
    - regex: ^test
    - not:
        has:
          pattern: expect($$$)

# Any condition can match (OR)
rule:
  any:
    - pattern: console.log($$$)
    - pattern: console.error($$$)
    - pattern: console.warn($$$)

# Negate a condition (NOT)
rule:
  pattern: function $NAME($$$) { $$$ }
  not:
    has:
      pattern: return $$$
```

### Complete Example Rules

#### Example 1: No Await in Promise.all

```yaml
id: no-await-in-promise-all
language: typescript
severity: warning
message: Don't use await inside Promise.all() - it defeats parallel execution
rule:
  pattern: Promise.all($ARGS)
  has:
    pattern: await $_
    stopBy: end
note: |
  Bad:  await Promise.all([await fetch(a), await fetch(b)])
  Good: await Promise.all([fetch(a), fetch(b)])
```

#### Example 2: Optional Chaining Migration

```yaml
id: use-optional-chaining
language: typescript
severity: info
message: Use optional chaining for safer property access
rule:
  any:
    - pattern: $OBJ && $OBJ.$PROP
    - pattern: $OBJ && $OBJ.$METHOD($$$)
fix: |
  $OBJ?.$PROP
note: Convert logical AND checks to optional chaining
```

#### Example 3: React Hook Dependencies

```yaml
id: exhaustive-deps
language: typescript
message: useEffect missing dependency
rule:
  pattern: |
    useEffect(() => {
      $$$
      $VAR
      $$$
    }, [$$$DEPS])
  not:
    any:
      - regex: \b$VAR\b
        field: DEPS
```

## Advanced Features

### Transformations

Transform meta variable content before using in fix:

#### Case Conversion

```yaml
id: rename-to-snake-case
language: python
rule:
  pattern: def $FUNC($$$): $$$
fix: def $FUNC_SNAKE($$$): $$$
transform:
  FUNC_SNAKE:
    convert:
      source: $FUNC
      toCase: snakeCase
```

Available case conversions:
- `camelCase`, `PascalCase`, `snake_case`, `SCREAMING_SNAKE_CASE`, `kebab-case`

#### Regex Replace

```yaml
transform:
  NEW_VAR:
    replace:
      source: $OLD_VAR
      replace: ^get(.+)$
      by: set$1
```

#### Substring/Slice

```yaml
transform:
  FIRST_CHAR:
    substring:
      source: $STRING
      startChar: 0
      endChar: 1
```

### Rewriters (Advanced)

Rewriters allow complex transformations on meta variable children:

```yaml
id: transform-imports
language: typescript
rule:
  pattern: |
    import { $$$IMPORTS } from '$MODULE'
fix: |
  import $NEW_IMPORTS from '$MODULE'
transform:
  NEW_IMPORTS:
    rewrite:
      source: $$$IMPORTS
      rewriters:
        - id: named-import
          rule:
            kind: import_specifier
          fix: '* as $LOCAL'
```

### Utilities (Reusable Patterns)

Define reusable patterns across rules:

```yaml
utils:
  is-console-method:
    any:
      - pattern: console.log($$$)
      - pattern: console.error($$$)
      - pattern: console.warn($$$)

rule:
  matches: is-console-method
  inside:
    pattern: |
      function $FUNC($$$) {
        $$$
      }
```

## Common Refactoring Patterns

### JavaScript/TypeScript

#### Optional Chaining
```yaml
id: optional-chaining
language: typescript
rule:
  any:
    - pattern: $A && $A()
    - pattern: $A && $A.$B
    - pattern: $A != null && $A.$B
fix: $A?.$B  # or $A?.()
```

#### Logical Assignment
```yaml
id: logical-assignment
language: javascript
rule:
  any:
    - pattern: $A = $A || $B
    - pattern: $A = $A ?? $B
    - pattern: $A = $A && $B
fix: $A ||= $B  # or ??=, &&=
```

#### Async/Await
```yaml
id: promise-to-async
language: typescript
rule:
  pattern: |
    $FUNC().then($CB)
fix: |
  await $FUNC()
```

### Python

#### List Comprehension
```yaml
id: use-list-comprehension
language: python
rule:
  pattern: |
    $RESULT = []
    for $ITEM in $ITER:
      $RESULT.append($EXPR)
fix: |
  $RESULT = [$EXPR for $ITEM in $ITER]
```

#### Walrus Operator
```yaml
id: use-walrus
language: python
rule:
  pattern: |
    if $FUNC($$$):
      $VAR = $FUNC($$$)
fix: |
  if ($VAR := $FUNC($$$)):
    pass
```

### React

#### Hook Dependencies
```yaml
id: fix-use-effect-deps
language: typescript
rule:
  pattern: |
    useEffect(() => {
      $$$BODY
    })
fix: |
  useEffect(() => {
    $$$BODY
  }, [])
```

#### Event Handler Binding
```yaml
id: use-arrow-functions
language: typescript
rule:
  pattern: onClick={$FUNC.bind(this)}
fix: onClick={() => $FUNC()}
```

## Workflow Integration

### Step 1: Explore with Search

Before rewriting, always search first to understand impact:

```bash
# Find all matches
ast-grep -p '$PATTERN' -l typescript

# Count how many will be affected
ast-grep -p '$PATTERN' -l typescript --json | jq 'length'

# Review each match location
ast-grep -p '$PATTERN' -l typescript | less
```

### Step 2: Test Rewrite Interactively

```bash
# Use --interactive to review each change
ast-grep \
  -p '$PATTERN' \
  --rewrite '$FIX' \
  -l typescript \
  --interactive
```

### Step 3: Apply with Version Control

```bash
# Ensure clean git state
git status

# Apply rewrite
ast-grep -p '$PATTERN' --rewrite '$FIX' -l typescript

# Review changes
git diff

# If good, commit; if bad, revert
git commit -am "refactor: apply ast-grep transformation"
# or
git checkout .
```

### Step 4: Create Reusable Rules

For repeated transformations, save as YAML:

```bash
# Create rule file
cat > .ast-grep/rules/my-rule.yml << 'EOF'
id: my-transformation
language: typescript
rule:
  pattern: $PATTERN
fix: $FIX
EOF

# Apply rule
ast-grep scan --rule .ast-grep/rules/my-rule.yml
```

## Best Practices

### Pattern Design

1. **Start simple, iterate**
   ```bash
   # Start broad
   ast-grep -p 'console.log($$$)' -l typescript

   # Narrow down
   ast-grep -p 'console.log($MSG)' -l typescript  # Only single arg
   ```

2. **Test patterns in playground**
   - Visit https://ast-grep.github.io/playground.html
   - Paste sample code and test patterns interactively
   - Verify pattern matches expected structures

3. **Use descriptive meta variable names**
   ```yaml
   # Good
   pattern: function $HANDLER_NAME($EVENT) { $$$ }

   # Less clear
   pattern: function $A($B) { $$$ }
   ```

4. **Consider edge cases**
   ```yaml
   # Account for optional parameters, different styles, etc.
   rule:
     any:
       - pattern: 'function $NAME($$$) { $$$ }'
       - pattern: 'const $NAME = ($$$) => { $$$ }'
       - pattern: 'const $NAME = function($$$) { $$$ }'
   ```

### Safety

1. **Always use version control**
   - Commit before running rewrites
   - Review diffs carefully before pushing

2. **Use interactive mode for unfamiliar transforms**
   ```bash
   ast-grep -p '$PAT' --rewrite '$FIX' -l ts --interactive
   ```

3. **Test on subset first**
   ```bash
   # Test on one file
   ast-grep -p '$PAT' --rewrite '$FIX' -l ts src/utils/single-file.ts

   # Then expand to directory
   ast-grep -p '$PAT' --rewrite '$FIX' -l ts src/
   ```

4. **Run tests after transformations**
   ```bash
   ast-grep -p '$PAT' --rewrite '$FIX' -l ts
   npm test  # Verify nothing broke
   ```

### Performance

1. **Specify file paths when possible**
   ```bash
   # Slower: searches entire directory tree
   ast-grep -p '$PAT' -l ts

   # Faster: searches specific directory
   ast-grep -p '$PAT' -l ts src/components/
   ```

2. **Use appropriate language**
   ```bash
   # Faster: only parses .ts/.tsx files
   ast-grep -p '$PAT' -l typescript

   # Slower: parses all files
   ast-grep -p '$PAT'
   ```

3. **Combine with file filters**
   ```bash
   # Search only specific file patterns
   find src -name "*.test.ts" | xargs ast-grep -p '$PAT' -l typescript
   ```

## Troubleshooting

### Pattern Doesn't Match

1. **Verify pattern is valid code**
   ```bash
   # Check if your pattern would compile
   echo 'your pattern here' > temp.ts
   tsc --noEmit temp.ts  # Should have no syntax errors
   ```

2. **Check AST structure**
   - Use the playground to inspect AST nodes
   - Your pattern must match the exact tree structure

3. **Try broader patterns**
   ```bash
   # Too specific
   ast-grep -p 'function foo() { return 42; }' -l typescript

   # More flexible
   ast-grep -p 'function foo() { $$$ }' -l typescript
   ```

### Rewrite Produces Invalid Code

1. **Check meta variable usage**
   - Ensure all meta variables in fix are captured in pattern
   - Use same variable names exactly

2. **Test pattern captures correct nodes**
   ```bash
   # First verify what gets captured
   ast-grep -p '$PATTERN' -l ts --json | jq '.[-1].metaVariables'
   ```

3. **Consider indentation/formatting**
   - ast-grep preserves indentation from fix template
   - Run formatter after rewrites: `npm run format`

### Performance Issues

1. **Limit search scope**
   ```bash
   # Bad: searches everything including node_modules
   ast-grep -p '$PAT' -l ts

   # Good: explicit directory
   ast-grep -p '$PAT' -l ts src/
   ```

2. **Use simpler patterns**
   - Complex nested patterns are slower
   - Consider multiple passes with simpler patterns

## Reference

### Command Cheat Sheet

```bash
# Search
sg -p 'PATTERN' -l LANG [PATH]

# Rewrite
sg -p 'PATTERN' --rewrite 'FIX' -l LANG --interactive

# With YAML rule
sg scan --rule rules/my-rule.yml

# Output as JSON
sg -p 'PATTERN' -l LANG --json

# Context lines
sg -p 'PATTERN' -l LANG -A 3 -B 3
```

### Language Identifiers

Common languages:
- TypeScript: `typescript`, `ts`, `tsx`
- JavaScript: `javascript`, `js`, `jsx`
- Python: `python`, `py`
- Rust: `rust`, `rs`
- Go: `go`
- Java: `java`
- C/C++: `c`, `cpp`
- HTML/CSS: `html`, `css`

### Meta Variable Syntax

- `$VAR` - Single AST node
- `$$$` or `$$$VAR` - Multiple AST nodes
- `$_VAR` - Anonymous (non-capturing) variable
- Variable names: uppercase letters, digits, underscores only

## Resources

- Official Docs: https://ast-grep.github.io/
- Pattern Playground: https://ast-grep.github.io/playground.html
- Rule Catalog: https://ast-grep.github.io/catalog/
- GitHub: https://github.com/ast-grep/ast-grep

## Decision Framework

Use this skill when:
- ✅ Need to search/replace code based on structure
- ✅ Want language-aware refactoring
- ✅ Need to avoid false matches from text search
- ✅ Transforming code patterns (not just renaming)
- ✅ Working with supported languages

Use other tools when:
- ❌ Simple string search (use grep)
- ❌ Non-code files (use grep/sed)
- ❌ Performance-critical searches (grep is faster)
- ❌ Language not supported by tree-sitter
