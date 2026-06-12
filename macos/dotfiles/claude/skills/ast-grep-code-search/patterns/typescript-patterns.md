# TypeScript/JavaScript Common Patterns

Quick reference for frequently used ast-grep patterns in TypeScript and JavaScript codebases.

## Function Patterns

### Find All Function Declarations
```bash
ast-grep -p 'function $NAME($$$) { $$$ }' -l typescript
```

### Find Arrow Functions
```bash
ast-grep -p 'const $NAME = ($$$) => { $$$ }' -l typescript
```

### Find Async Functions
```bash
ast-grep -p 'async function $NAME($$$) { $$$ }' -l typescript
```

### Find Functions with Specific Parameter
```bash
# Find functions accepting 'event' parameter
ast-grep -p 'function $NAME($$$, event, $$$) { $$$ }' -l typescript
```

## React Patterns

### Find useState Hooks
```bash
ast-grep -p 'useState($INIT)' -l typescript
```

### Find useEffect Hooks
```bash
# Without dependencies
ast-grep -p 'useEffect(() => { $$$ })' -l typescript

# With dependencies
ast-grep -p 'useEffect(() => { $$$ }, [$$$DEPS])' -l typescript

# Empty dependency array
ast-grep -p 'useEffect(() => { $$$ }, [])' -l typescript
```

### Find useCallback Hooks
```bash
ast-grep -p 'useCallback(() => { $$$ }, [$$$])' -l typescript
```

### Find Component Props Destructuring
```bash
ast-grep -p 'function $COMP({ $$$PROPS }: $TYPE) { $$$ }' -l typescript
```

### Find JSX Event Handlers
```bash
ast-grep -p 'onClick={$HANDLER}' -l tsx
ast-grep -p 'onChange={$HANDLER}' -l tsx
```

## Import/Export Patterns

### Find All Imports from Module
```bash
ast-grep -p "import $$$FROM from '@/components'" -l typescript
```

### Find Named Imports
```bash
ast-grep -p "import { $$$NAMES } from '$MODULE'" -l typescript
```

### Find Default Imports
```bash
ast-grep -p "import $NAME from '$MODULE'" -l typescript
```

### Find Dynamic Imports
```bash
ast-grep -p 'import($PATH)' -l typescript
```

### Find Exports
```bash
# Default export
ast-grep -p 'export default $EXPR' -l typescript

# Named export
ast-grep -p 'export { $$$NAMES }' -l typescript

# Re-exports
ast-grep -p "export * from '$MODULE'" -l typescript
```

## Promise/Async Patterns

### Find Promise Chains
```bash
ast-grep -p '$PROMISE.then($CALLBACK)' -l typescript
```

### Find Promise.all Usage
```bash
ast-grep -p 'Promise.all($ARRAY)' -l typescript
```

### Find Await Expressions
```bash
ast-grep -p 'await $EXPR' -l typescript
```

### Find try/catch with Promises
```bash
ast-grep -p 'try { $$$AWAIT $$$ } catch ($ERR) { $$$ }' -l typescript
```

## Object/Class Patterns

### Find Class Declarations
```bash
ast-grep -p 'class $NAME { $$$ }' -l typescript
```

### Find Class with Extends
```bash
ast-grep -p 'class $NAME extends $BASE { $$$ }' -l typescript
```

### Find Class Methods
```bash
ast-grep -p 'class $CLASS { $METHOD($$$) { $$$ } }' -l typescript
```

### Find Constructor
```bash
ast-grep -p 'constructor($$$) { $$$ }' -l typescript
```

### Find Object Property Access
```bash
# Dot notation
ast-grep -p '$OBJ.$PROP' -l typescript

# Bracket notation
ast-grep -p '$OBJ[$KEY]' -l typescript
```

### Find Object Destructuring
```bash
ast-grep -p 'const { $$$PROPS } = $OBJ' -l typescript
```

## Type/Interface Patterns

### Find Interface Declarations
```bash
ast-grep -p 'interface $NAME { $$$ }' -l typescript
```

### Find Type Aliases
```bash
ast-grep -p 'type $NAME = $TYPE' -l typescript
```

### Find Generic Types
```bash
ast-grep -p '$TYPE<$GENERIC>' -l typescript
```

## Console/Logging Patterns

### Find All Console Methods
```bash
ast-grep -p 'console.$METHOD($$$)' -l typescript
```

### Find Specific Console Methods
```bash
ast-grep -p 'console.log($$$)' -l typescript
ast-grep -p 'console.error($$$)' -l typescript
ast-grep -p 'console.warn($$$)' -l typescript
```

## Conditional Patterns

### Find If Statements
```bash
ast-grep -p 'if ($COND) { $$$ }' -l typescript
```

### Find Ternary Operators
```bash
ast-grep -p '$COND ? $TRUE : $FALSE' -l typescript
```

### Find Null Checks
```bash
# Strict null check
ast-grep -p '$VAR === null' -l typescript
ast-grep -p '$VAR !== null' -l typescript

# Loose null check
ast-grep -p '$VAR == null' -l typescript
ast-grep -p '$VAR != null' -l typescript
```

### Find Logical AND/OR
```bash
ast-grep -p '$A && $B' -l typescript
ast-grep -p '$A || $B' -l typescript
ast-grep -p '$A ?? $B' -l typescript
```

## Common Refactoring Patterns

### Optional Chaining Opportunities
```bash
# Find: $OBJ && $OBJ.prop
ast-grep -p '$OBJ && $OBJ.$PROP' -l typescript --rewrite '$OBJ?.$PROP'

# Find: $OBJ && $OBJ()
ast-grep -p '$OBJ && $OBJ()' -l typescript --rewrite '$OBJ?.()'

# Find: $OBJ != null && $OBJ.prop
ast-grep -p '$OBJ != null && $OBJ.$PROP' -l typescript --rewrite '$OBJ?.$PROP'
```

### Logical Assignment Operators
```bash
# OR assignment
ast-grep -p '$A = $A || $B' -l typescript --rewrite '$A ||= $B'

# AND assignment
ast-grep -p '$A = $A && $B' -l typescript --rewrite '$A &&= $B'

# Nullish assignment
ast-grep -p '$A = $A ?? $B' -l typescript --rewrite '$A ??= $B'
```

### Async/Await Migration
```bash
# Promise.then to async/await
ast-grep -p '$PROMISE.then($CB)' -l typescript

# Note: Full rewrite requires more complex rule
```

### Array Methods
```bash
# Find forEach
ast-grep -p '$ARRAY.forEach($CALLBACK)' -l typescript

# Find map
ast-grep -p '$ARRAY.map($CALLBACK)' -l typescript

# Find filter
ast-grep -p '$ARRAY.filter($PREDICATE)' -l typescript

# Find reduce
ast-grep -p '$ARRAY.reduce($REDUCER, $INIT)' -l typescript
```

## Error Handling Patterns

### Find try/catch Blocks
```bash
ast-grep -p 'try { $$$ } catch ($ERR) { $$$ }' -l typescript
```

### Find throw Statements
```bash
ast-grep -p 'throw $ERROR' -l typescript
ast-grep -p 'throw new $ERROR($MSG)' -l typescript
```

### Find Error Constructors
```bash
ast-grep -p 'new Error($MSG)' -l typescript
```

## Testing Patterns

### Find Test Blocks
```bash
# Jest/Vitest
ast-grep -p "describe('$DESC', () => { $$$ })" -l typescript
ast-grep -p "it('$DESC', () => { $$$ })" -l typescript
ast-grep -p "test('$DESC', () => { $$$ })" -l typescript
```

### Find Assertions
```bash
# Jest
ast-grep -p 'expect($ACTUAL).toBe($EXPECTED)' -l typescript
ast-grep -p 'expect($ACTUAL).toEqual($EXPECTED)' -l typescript

# Chai
ast-grep -p '$ACTUAL.should.equal($EXPECTED)' -l typescript
```

### Find Mocks
```bash
ast-grep -p 'jest.mock($MODULE)' -l typescript
ast-grep -p 'vi.mock($MODULE)' -l typescript
```

## TypeScript-Specific Patterns

### Find Type Assertions
```bash
# as syntax
ast-grep -p '$EXPR as $TYPE' -l typescript

# Angle bracket syntax
ast-grep -p '<$TYPE>$EXPR' -l typescript
```

### Find Non-null Assertions
```bash
ast-grep -p '$EXPR!' -l typescript
```

### Find Type Guards
```bash
ast-grep -p 'function $NAME($PARAM): $PARAM is $TYPE { $$$ }' -l typescript
```

### Find Enum Declarations
```bash
ast-grep -p 'enum $NAME { $$$ }' -l typescript
```

## Variable Declaration Patterns

### Find const/let/var
```bash
ast-grep -p 'const $NAME = $VALUE' -l typescript
ast-grep -p 'let $NAME = $VALUE' -l typescript
ast-grep -p 'var $NAME = $VALUE' -l typescript
```

### Find Uninitialized Variables
```bash
ast-grep -p 'let $NAME' -l typescript
```

### Find Array Destructuring
```bash
ast-grep -p 'const [$$$ITEMS] = $ARRAY' -l typescript
```

## Tips for Pattern Writing

1. **Test in Playground First**: https://ast-grep.github.io/playground.html
2. **Start Broad**: Begin with simple pattern, refine as needed
3. **Check Valid Syntax**: Pattern must be parseable code
4. **Use $$$ for Flexibility**: Matches zero or more nodes
5. **Consider Edge Cases**: Different syntax styles, optional parts
6. **Name Variables Descriptively**: $HANDLER vs $A
7. **Combine with Grep**: Use grep for text, ast-grep for structure

## Example Workflow

```bash
# 1. Find all instances
ast-grep -p '$PATTERN' -l typescript

# 2. Count matches
ast-grep -p '$PATTERN' -l typescript --json | jq 'length'

# 3. Test rewrite on one file
ast-grep -p '$PATTERN' --rewrite '$FIX' -l typescript src/file.ts

# 4. Apply interactively
ast-grep -p '$PATTERN' --rewrite '$FIX' -l typescript --interactive

# 5. Apply to all
ast-grep -p '$PATTERN' --rewrite '$FIX' -l typescript
```
