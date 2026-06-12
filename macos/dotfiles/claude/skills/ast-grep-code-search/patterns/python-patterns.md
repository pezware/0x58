# Python Common Patterns

Quick reference for frequently used ast-grep patterns in Python codebases.

## Function Patterns

### Find Function Definitions
```bash
ast-grep -p 'def $NAME($$$): $$$' -l python
```

### Find Functions with Decorators
```bash
ast-grep -p '@$DECORATOR
def $NAME($$$): $$$' -l python
```

### Find Async Functions
```bash
ast-grep -p 'async def $NAME($$$): $$$' -l python
```

### Find Lambda Functions
```bash
ast-grep -p 'lambda $$$: $EXPR' -l python
```

## Class Patterns

### Find Class Definitions
```bash
ast-grep -p 'class $NAME: $$$' -l python
```

### Find Class with Inheritance
```bash
ast-grep -p 'class $NAME($BASE): $$$' -l python
```

### Find __init__ Methods
```bash
ast-grep -p 'def __init__(self, $$$): $$$' -l python
```

### Find Class Methods
```bash
ast-grep -p '@classmethod
def $NAME(cls, $$$): $$$' -l python
```

### Find Static Methods
```bash
ast-grep -p '@staticmethod
def $NAME($$$): $$$' -l python
```

## Import Patterns

### Find Import Statements
```bash
ast-grep -p 'import $MODULE' -l python
```

### Find From Imports
```bash
ast-grep -p 'from $MODULE import $$$' -l python
```

### Find Specific Imports
```bash
# Import specific function
ast-grep -p 'from $MODULE import $FUNC' -l python

# Import with alias
ast-grep -p 'import $MODULE as $ALIAS' -l python
```

## List/Dict Comprehensions

### Find List Comprehensions
```bash
ast-grep -p '[$EXPR for $VAR in $ITER]' -l python
```

### Find Dict Comprehensions
```bash
ast-grep -p '{$KEY: $VAL for $VAR in $ITER}' -l python
```

### Find Generator Expressions
```bash
ast-grep -p '($EXPR for $VAR in $ITER)' -l python
```

### Find Set Comprehensions
```bash
ast-grep -p '{$EXPR for $VAR in $ITER}' -l python
```

## Control Flow Patterns

### Find If Statements
```bash
ast-grep -p 'if $COND: $$$' -l python
```

### Find If/Else
```bash
ast-grep -p 'if $COND: $$$
else: $$$' -l python
```

### Find For Loops
```bash
ast-grep -p 'for $VAR in $ITER: $$$' -l python
```

### Find While Loops
```bash
ast-grep -p 'while $COND: $$$' -l python
```

### Find Match Statements (Python 3.10+)
```bash
ast-grep -p 'match $EXPR:
    case $PATTERN: $$$' -l python
```

## Exception Handling

### Find try/except Blocks
```bash
ast-grep -p 'try:
    $$$
except $ERR:
    $$$' -l python
```

### Find try/except/finally
```bash
ast-grep -p 'try:
    $$$
except $ERR:
    $$$
finally:
    $$$' -l python
```

### Find Raise Statements
```bash
ast-grep -p 'raise $ERROR' -l python
ast-grep -p 'raise $ERROR($MSG)' -l python
```

## Context Managers

### Find with Statements
```bash
ast-grep -p 'with $CONTEXT as $VAR: $$$' -l python
```

### Find Multiple Context Managers
```bash
ast-grep -p 'with $A as $B, $C as $D: $$$' -l python
```

## Variable/Assignment Patterns

### Find Variable Assignment
```bash
ast-grep -p '$VAR = $VALUE' -l python
```

### Find Multiple Assignment
```bash
ast-grep -p '$A, $B = $VALUES' -l python
```

### Find Augmented Assignment
```bash
ast-grep -p '$VAR += $VALUE' -l python
ast-grep -p '$VAR -= $VALUE' -l python
ast-grep -p '$VAR *= $VALUE' -l python
```

### Find Walrus Operator (Python 3.8+)
```bash
ast-grep -p '($VAR := $VALUE)' -l python
```

## Type Hints (Python 3.5+)

### Find Typed Function Parameters
```bash
ast-grep -p 'def $NAME($PARAM: $TYPE): $$$' -l python
```

### Find Function Return Types
```bash
ast-grep -p 'def $NAME($$$) -> $TYPE: $$$' -l python
```

### Find Typed Variables
```bash
ast-grep -p '$VAR: $TYPE = $VALUE' -l python
```

## Common Library Patterns

### Django

#### Find Models
```bash
ast-grep -p 'class $MODEL(models.Model): $$$' -l python
```

#### Find Views
```bash
ast-grep -p 'def $VIEW(request): $$$' -l python
```

#### Find URL Patterns
```bash
ast-grep -p "path('$ROUTE', $VIEW)" -l python
```

### Flask

#### Find Routes
```bash
ast-grep -p "@app.route('$ROUTE')
def $VIEW(): $$$" -l python
```

### FastAPI

#### Find Endpoints
```bash
ast-grep -p "@app.get('$ROUTE')
async def $ENDPOINT($$$): $$$" -l python
```

### Pytest

#### Find Test Functions
```bash
ast-grep -p 'def test_$NAME($$$): $$$' -l python
```

#### Find Fixtures
```bash
ast-grep -p '@pytest.fixture
def $FIXTURE($$$): $$$' -l python
```

## Data Structure Patterns

### Find Dictionary Access
```bash
ast-grep -p '$DICT[$KEY]' -l python
```

### Find Dictionary Get
```bash
ast-grep -p '$DICT.get($KEY)' -l python
ast-grep -p '$DICT.get($KEY, $DEFAULT)' -l python
```

### Find List Append
```bash
ast-grep -p '$LIST.append($ITEM)' -l python
```

### Find List Extend
```bash
ast-grep -p '$LIST.extend($ITEMS)' -l python
```

## String Formatting

### Find f-strings
```bash
ast-grep -p 'f"$$$"' -l python
```

### Find .format() Calls
```bash
ast-grep -p '"$STR".format($$$)' -l python
```

### Find % Formatting
```bash
ast-grep -p '"$STR" % $ARGS' -l python
```

## Common Refactoring Patterns

### Walrus Operator Opportunities
```bash
# Pattern: if condition that assigns
# Find:
if $FUNC($$$):
    $VAR = $FUNC($$$)

# Can be refactored to:
if ($VAR := $FUNC($$$)):
    pass
```

### List Comprehension Opportunities
```bash
# Find loops that build lists
# Pattern:
$RESULT = []
for $ITEM in $ITER:
    $RESULT.append($EXPR)

# Refactor to:
$RESULT = [$EXPR for $ITEM in $ITER]
```

### Dict Get with Default
```bash
# Find: $DICT[$KEY] if $KEY in $DICT else $DEFAULT
# Rewrite: $DICT.get($KEY, $DEFAULT)
```

### Join Instead of Loop
```bash
# Find loops that build strings
# Pattern:
$RESULT = ""
for $ITEM in $ITER:
    $RESULT += $ITEM
```

## Python 3.10+ Match/Case Patterns

### Find Match Statements
```bash
ast-grep -p 'match $VAR:
    case $PATTERN:
        $$$' -l python
```

### Find Specific Case Patterns
```bash
ast-grep -p 'case $VALUE:
    $$$' -l python
```

## Async/Await Patterns

### Find Async Functions
```bash
ast-grep -p 'async def $NAME($$$): $$$' -l python
```

### Find Await Expressions
```bash
ast-grep -p 'await $EXPR' -l python
```

### Find Async Context Managers
```bash
ast-grep -p 'async with $CONTEXT as $VAR: $$$' -l python
```

### Find Async Comprehensions
```bash
ast-grep -p '[$EXPR async for $VAR in $ITER]' -l python
```

## Dataclass Patterns (Python 3.7+)

### Find Dataclasses
```bash
ast-grep -p '@dataclass
class $NAME: $$$' -l python
```

### Find Dataclass Fields
```bash
ast-grep -p '$FIELD: $TYPE = field($$$)' -l python
```

## Property Patterns

### Find @property Decorators
```bash
ast-grep -p '@property
def $NAME(self): $$$' -l python
```

### Find Setters
```bash
ast-grep -p '@$PROP.setter
def $NAME(self, $VALUE): $$$' -l python
```

## Common Anti-patterns to Find

### Mutable Default Arguments
```bash
# Find functions with mutable defaults (anti-pattern)
ast-grep -p 'def $NAME($PARAM=[]): $$$' -l python
ast-grep -p 'def $NAME($PARAM={}): $$$' -l python
```

### Bare Except
```bash
# Find bare except clauses (anti-pattern)
ast-grep -p 'except:
    $$$' -l python
```

### == None Instead of is None
```bash
ast-grep -p '$VAR == None' -l python
```

## Example Workflow

```bash
# 1. Find all function definitions
ast-grep -p 'def $NAME($$$): $$$' -l python

# 2. Find functions with specific decorator
ast-grep -p '@app.route($$$)
def $VIEW($$$): $$$' -l python

# 3. Count matches
ast-grep -p 'def $NAME($$$): $$$' -l python --json | jq 'length'

# 4. Apply refactoring interactively
ast-grep \
  -p '$VAR = $VAR or $DEFAULT' \
  --rewrite '$VAR = $VAR or $DEFAULT' \
  -l python \
  --interactive
```

## Tips

1. **Python Indentation Matters**: Pattern must match indentation structure
2. **Use $$$ for Suites**: Python uses suites (indented blocks), use $$$ to match them
3. **Multiline Patterns**: Use proper indentation in pattern strings
4. **Test Simple First**: Start with simple patterns, add complexity gradually
5. **Check Python Version**: Some syntax only available in newer Python versions
