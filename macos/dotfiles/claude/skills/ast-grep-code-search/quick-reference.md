# ast-grep Quick Reference Card

One-page reference for ast-grep commands and patterns.

## Basic Commands

```bash
# Search
ast-grep -p 'PATTERN' -l LANG [PATH]
sg -p 'PATTERN' -l LANG                    # Short alias

# Rewrite
ast-grep -p 'PATTERN' --rewrite 'FIX' -l LANG --interactive

# With YAML rule
ast-grep scan --rule path/to/rule.yml

# Output as JSON
ast-grep -p 'PATTERN' -l LANG --json
```

## Meta Variables

| Syntax | Matches | Example |
|--------|---------|---------|
| `$VAR` | Single AST node | `console.log($MSG)` |
| `$$$` | Multiple nodes (0+) | `function f($$$) { $$$ }` |
| `$_VAR` | Anonymous (no capture) | `$_FUNC($_ARG)` |

## Common Patterns

### TypeScript/JavaScript
```bash
# Functions
'function $NAME($$$) { $$$ }'
'const $NAME = ($$$) => { $$$ }'
'async function $NAME($$$) { $$$ }'

# React
'useState($INIT)'
'useEffect(() => { $$$ }, [$$$])'

# Imports
"import $NAME from '$MODULE'"
"import { $$$NAMES } from '$MODULE'"

# Promises
'await $EXPR'
'Promise.all($$$)'
'$PROMISE.then($CALLBACK)'

# Objects
'$OBJ.$PROP'
'const { $$$PROPS } = $OBJ'

# Console
'console.log($$$)'
'console.error($$$)'
```

### Python
```bash
# Functions
'def $NAME($$$): $$$'
'async def $NAME($$$): $$$'
'lambda $$$: $EXPR'

# Classes
'class $NAME: $$$'
'class $NAME($BASE): $$$'
'def __init__(self, $$$): $$$'

# Imports
'import $MODULE'
'from $MODULE import $$$'

# Comprehensions
'[$EXPR for $VAR in $ITER]'
'{$KEY: $VAL for $VAR in $ITER}'

# Control flow
'if $COND: $$$'
'for $VAR in $ITER: $$$'
'with $CTX as $VAR: $$$'

# Exception handling
'try: $$$\nexcept $ERR: $$$'
'raise $ERROR'
```

## YAML Rule Structure

```yaml
id: unique-rule-id
language: typescript
severity: warning | error | info
message: Human readable message

rule:
  pattern: $PATTERN          # or kind, regex, etc.

fix: $FIX_PATTERN            # Optional: for auto-fix

note: |                      # Optional: detailed explanation
  Additional context here
```

## Rule Types

### Atomic Rules
```yaml
rule:
  pattern: console.log($$$)        # Match code pattern
  kind: function_declaration       # Match AST node type
  regex: ^test_.*                  # Match node text
```

### Relational Rules
```yaml
rule:
  pattern: $NODE
  inside:    { pattern: ... }      # Find inside another node
  has:       { pattern: ... }      # Has child matching
  follows:   { pattern: ... }      # Comes after
  precedes:  { pattern: ... }      # Comes before
```

### Composite Rules
```yaml
rule:
  all:       # All must match (AND)
    - pattern: ...
    - regex: ...

  any:       # Any can match (OR)
    - pattern: ...
    - pattern: ...

  not:       # Must NOT match
    pattern: ...
```

## Transformations

```yaml
transform:
  NEW_VAR:
    # Case conversion
    convert:
      source: $OLD_VAR
      toCase: camelCase    # PascalCase, snake_case, kebab-case, etc.

    # Regex replace
    replace:
      source: $VAR
      replace: ^get(.+)$
      by: set$1

    # Substring
    substring:
      source: $VAR
      startChar: 0
      endChar: 5

    # Rewriter (advanced)
    rewrite:
      source: $$$VAR
      rewriters: [...]
```

## Language Identifiers

| Language | Identifier |
|----------|-----------|
| TypeScript | `typescript`, `ts`, `tsx` |
| JavaScript | `javascript`, `js`, `jsx` |
| Python | `python`, `py` |
| Rust | `rust`, `rs` |
| Go | `go` |
| Java | `java` |
| C/C++ | `c`, `cpp` |
| HTML/CSS | `html`, `css` |

## Common Refactoring Examples

### Optional Chaining
```bash
ast-grep \
  -p '$OBJ && $OBJ.$PROP' \
  --rewrite '$OBJ?.$PROP' \
  -l typescript --interactive
```

### Logical Assignment
```bash
ast-grep \
  -p '$A = $A || $B' \
  --rewrite '$A ||= $B' \
  -l javascript --interactive
```

### Function Rename
```bash
ast-grep \
  -p 'oldFunction($$$)' \
  --rewrite 'newFunction($$$)' \
  -l typescript
```

## Output Options

```bash
# Default: show matches with context
ast-grep -p 'PATTERN' -l LANG

# JSON output
ast-grep -p 'PATTERN' -l LANG --json

# Count matches
ast-grep -p 'PATTERN' -l LANG --json | jq 'length'

# Just filenames
ast-grep -p 'PATTERN' -l LANG --json | jq -r '.file' | uniq

# With context lines
ast-grep -p 'PATTERN' -l LANG -A 3 -B 3
```

## Best Practices

1. **Test in Playground**: https://ast-grep.github.io/playground.html
2. **Start Simple**: Begin with broad pattern, refine iteratively
3. **Use Version Control**: Always commit before bulk rewrites
4. **Interactive Mode**: Use `--interactive` for unfamiliar transforms
5. **Validate Pattern**: Pattern must be valid, parseable code
6. **Name Variables**: Use descriptive meta variable names
7. **Test on Subset**: Try on single file before full directory
8. **Run Tests After**: Verify changes with test suite

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Pattern doesn't match | Verify pattern is valid syntax |
| Too many matches | Make pattern more specific |
| No matches | Use broader pattern with `$$$` |
| Invalid rewrite | Check all meta vars captured in pattern |
| Slow search | Specify language and directory path |

## Resources

- Docs: https://ast-grep.github.io/
- Playground: https://ast-grep.github.io/playground.html
- Catalog: https://ast-grep.github.io/catalog/
- GitHub: https://github.com/ast-grep/ast-grep

## Typical Workflow

```bash
# 1. Search to understand scope
ast-grep -p '$PATTERN' -l typescript

# 2. Count affected files
ast-grep -p '$PATTERN' -l typescript --json | jq 'length'

# 3. Test on single file
ast-grep -p '$PATTERN' --rewrite '$FIX' -l typescript src/file.ts

# 4. Review interactively
ast-grep -p '$PATTERN' --rewrite '$FIX' -l typescript --interactive

# 5. Apply to all
ast-grep -p '$PATTERN' --rewrite '$FIX' -l typescript

# 6. Verify with git diff
git diff

# 7. Run tests
npm test

# 8. Commit or revert
git commit -am "refactor: apply transformation"
# or
git checkout .
```
