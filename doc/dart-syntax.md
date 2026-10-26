# Reading Dart's syntax: specification and plan

## Goal

Extend the `dart` format from tokens, pairs and declarations to Dart's
whole syntax: every declaration, including enum values and local
functions, every statement and every expression, as layer-3 elements over
the tokens. A keystroke must read again only as much as it can change: in
particular, typing in the name of a class edits that name and nothing
else.

## Where things stood before step 1

- **Layer 2**: tokens as Dart's scanner reads them, checked against
  `_fe_analyzer_shared` on every source file here and in libara. A token
  inside a string says what is open where it starts.
- **Layer 3**:
  - Pairs: `parens`, `brackets`, `braces`, `string`, `interpolation`.
  - Declarations at the top level and in class, mixin and extension
    bodies. Each is named for its kind and carries its `name`, which is
    indexed. They are checked against the analyzer's parser.
- **Edits**: a keystroke reads its declarations again from the declaration
  it falls in to the first one past it that ends where one ended before.
- **Not read yet**:
  - Statements and expressions.
  - Enum values and members.
  - Local functions.
  - Each name of `int a, b;` (only the first is kept).
- **Cost of a rename**: renaming a class reads the whole class again,
  because the class element carries the name, and an element's attributes
  change only when it is derived again. That is about 9ms for a
  1,500-line class.

## Requirements

1. **Renaming is local.** An edit inside the name of a declaration reads
   again that name's element and nothing more.
2. **Enums.** Each enum value is an element with its name and its
   arguments. Members after the values' `;` are read as a class's are.
3. **Functions.** Local function declarations, closures (function
   expressions), and formal parameter lists, with each parameter an
   element carrying its name. Type parameters likewise.
4. **Variables.** Each declarator of a variable or field declaration is a
   name of its own: `int a, b;` declares `a` and `b`.
5. **Statements.** Every Dart 3 statement form (listed below).
6. **Expressions.** Every Dart 3 expression form, with operator
   precedence and associativity as the language specification gives them,
   including collection literals, string interpolation, cascades and
   switch expressions.
7. **Patterns.** Dart 3 patterns in switch cases, `if`-`case`, pattern
   variable declarations and `for`-`in`.
8. **Incremental = fresh.** After any text edit, every layer equals what
   a fresh read of the new text gives. The randomized edit tests and the
   fuzz test enforce this, as they do for every format today.
9. **Recovery.** Text that does not parse becomes diagnostics, and what
   surrounds it still parses. An error never escapes the innermost pair
   it occurs in.
10. **Conformance.** On valid source, the elements agree with the
    analyzer's AST under the mapping given in Verification.
11. **Performance.**
    - Reading `lib/src/html/tree.dart` (62KB) stays within 100ms; today it
      is about 35ms.
    - A keystroke inside an identifier, a literal or a comment costs under
      1ms.
    - A keystroke anywhere else costs under 10ms at the 99th percentile.

## Design

### Elements of layer 3

An element exists for every construct that spans more than one token. A
construct of a single token, such as a name, a literal or `this`, is that
token and is not wrapped. Names are lower case, single words where
possible, and keep the kinds that exist today.

**Pairs** are kept as they are: `parens`, `brackets`, `braces`, `string`,
`interpolation`. They bound recovery and keep incremental reads cheap; see
the open questions.

**Declarations** keep their kinds: `class`, `mixin`, `enum`, `extension`,
`typedef`, `function`, `method`, `constructor`, `getter`, `setter`,
`field`, `variable` and `directive`. New ones:

| Element | Over | Notes |
|---|---|---|
| `value` | an enum value, from its name to its arguments | inside `enum` |
| `parameter` | one formal parameter | says `required`, `named` or `optional` where it is |
| `generic` | one type parameter, with its bound | |
| `initializer` | one entry of a constructor's initializer list | |
| `annotation` | `@` and what it names, with its arguments | |

**Names.** Each identifier that a declaration declares is covered by a
`name` element, one token long, saying the identifier as `name`. This
includes classes, members, parameters, local variables, local functions,
enum values, type parameters and pattern variables. `name` is the indexed
key, so `having(3, 'name')` finds every declared name. The declaration a
name belongs to is the innermost declaration around it. Declarations no
longer carry `name` themselves.

This is what makes a rename local. An edit inside an identifier that
stays an identifier changes no element's extent, so it needs only its
`name` element read again. A declaration whose attribute depended on the
name would have to be read again whole.

**Statements:**

| Element | Statement |
|---|---|
| `block` | `{ ... }` as a statement or a function body |
| `statement` | an expression followed by `;` |
| `if` | `if`, with its `else`; and `if (e case p)` |
| `for` | all three `for` forms, `await for` included |
| `while`, `do` | |
| `switch` | the statement; its `case` elements hold the patterns, guards and statements |
| `try` | with `catch` and `finally` elements inside |
| `return`, `break`, `continue`, `yield`, `assert` | |
| `label` | `name:` before a statement |
| `variable` | a local variable declaration, its declarators named |
| `function` | a local function declaration |

**Expressions:**

| Element | Expression | Attributes |
|---|---|---|
| `assignment` | `a = b`, `a += b`, ... | `operator` |
| `conditional` | `a ? b : c` | |
| `binary` | `a + b`, `a ?? b`, `a && b`, ... | `operator` |
| `prefix` | `-a`, `!a`, `++a`, `await a` | `operator` |
| `postfix` | `a++`, `a!` | `operator` |
| `is`, `as` | | |
| `throw` | | |
| `call` | a function or method call, `new` and `const` included | `const` where it is one |
| `argument` | a named argument | |
| `index` | `a[i]`, `a?[i]` | |
| `property` | `a.b`, `a?.b` | |
| `cascade` | the whole cascade, with a `section` for each `..` | |
| `closure` | a function expression | |
| `list`, `set`, `map`, `record` | collection and record literals | `const` where it is one |
| `entry` | `k: v` in a map | |
| `spread` | `...e`, `...?e` | |
| `if`, `for` | collection elements | |
| `switch` | a switch expression, with a `case` for each arm | |
| `instantiation` | type arguments that call nothing, as `f<int>` or `List<int>` | |
| `aware` | `?e` in a collection, left out where it is null | |
| `strings` | strings one after another, read as one | |
| `symbol` | `#name` | |

A parenthesized expression is its `parens` pair.

**Patterns** are `pattern` elements saying their `form`: `constant`,
`variable`, `wildcard`, `list`, `map`, `record`, `object`, `relational`,
`logical`, `cast`, `check` (`?`), `assert` (`!`) or `rest` (`...`).

**Types** of more than one token, such as `List<int>`, `int?`, function
types and record types, are `type` elements. A type of one token is its
token.

### Constructors

Whether a member is a constructor is read from the member alone, so that
no element's kind depends on another element's name:

- A member with a return type is never one.
- A member written with `factory` or `new`, as `const X(...)`, or with
  no return type as `X.y(...)`, is one.
- A member with no return type written `X(...)` is one where `X` is
  written as a type's name is, its first letter after any underscores a
  capital, and a method otherwise.

The analyzer compares `X` with the class's name instead. That cannot keep
a rename local: while a class `A` is being renamed, its constructor `A()`
would turn into a method at every keystroke. Untyped methods do occur,
such as `noSuchMethod(...)` and visitor overrides, and they are written
in lower case, as constructors' classes are not; the corpus test, where
every one of the analyzer's 449 files agrees, bears the convention out.

### The parser

The parser is hand-written recursive descent over the layer-2 tokens:
one function per grammar production, with precedence climbing for binary
operators. Whitespace and comments are skipped.

The pairs come first. Statements and expressions are parsed over tokens
whose brackets are already matched, so:

- **Recovery is bounded.** A parse error inside a pair is recovered at
  that pair's closing mark at the latest, so it never escapes into what
  holds the pair.
- **Lookahead is cheap.** "What follows this `(...)`" is one step,
  because a pair is a unit. That is how a closure `(a) {` is told from a
  parenthesized expression, and a record from a parenthesized one.
- **Diagnostics name what was expected**, as `expected ;` or `expected an
  expression` does, and parsing resumes:
  - in statements, at the next `;`, or the next token that starts a
    statement;
  - in a parameter or argument list, at the next `,`.

Where the grammar is ambiguous, these rules decide, as the language
specification and the analyzer do:

- **`<` starts type arguments** when what follows it parses as types, up
  to a `>` followed by `(`, `.`, `..`, `?.`, `=` or a token that cannot
  continue an expression. Otherwise it is less-than.
- **A `{` at the start of a statement** starts a block, not a map or set
  literal.
- **A statement starting with a type and a name** is a local variable or
  function declaration.
- **`(` after a name** is a call. `(` after `)`, `]` or `>` closing type
  arguments is a call of what it follows.
- **A pattern is read** wherever the grammar expects a pattern; nowhere
  else.

### Reading again after an edit

`affected` at layer 3 picks the smallest region it can prove enough. It
tries these in order:

1. **Inside a token.**
   - **When it applies:** each changed token is the same kind as the old
     token in its place, compared against the previous version, which
     libara keeps while it derives the new one. A name stays a name, a
     keyword keeps its text, string characters stay string characters, a
     comment stays a comment, and a mark is the same mark. The words a
     parse reads by their text, `type` and `_`, count as changed.
   - **Region:** the changed tokens, and the `name` elements over them.
   - **Effect:** no element's extent or kind changes, so only those `name`
     elements are read again, each with its new text. Requirement 1 comes
     down to this case: typing in a class's name is a change inside one
     name token, and the constructor rule depends on no name.
2. **A unit that reads alone.**
   - **Units:** a top-level declaration, a member, a block, a statement,
     and a closure's body.
   - **Choice:** the innermost unit around the change that, parsed from
     its start as the kind it was, ends where it ended, with no mark in it
     that closes nothing.
   - **What the old document supplies:** the unit's kind, and the context
     the parse starts in (for example, inside a switch case).
3. **The declarations window, as today.** Used where the change is
   directly at a declaring level.
4. **Everything,** where nothing smaller can be proved, or where a
   diagnostic touches the region.

`derive` at layer 3 reads the pairs, then the syntax, over the region.
Where the region is less than the whole text, it starts in the context
the old document says the region stands in.

### What does not change

- Layer 2, its tokens, and the scanner's checks.
- The pairs.
- `valid`: only string characters and comments are text.
- Structural edits are still refused.
- Dart still writes only a document read as Dart.

## Verification

- **Conformance with the analyzer.** For each source file, the analyzer's
  AST is mapped to the element vocabulary above, and the two are compared
  in pre-order as kind and token extent.
  - **The mapping** is a table in the test, one row per AST class. For
    example, `IfStatement` maps to `if`, `MethodInvocation` and
    `FunctionExpressionInvocation` to `call`, and `BinaryExpression` to
    `binary` with its operator.
  - **Left out:** AST nodes that wrap a single token, and
    `ParenthesizedExpression`, which is a pair here.
  - **Corpora:**
    - Every Dart file in this repository and in libara, in the default
      test run.
    - The `analyzer` package's own `lib`, 449 files and about 10MB, found
      through this package's resolved dependencies, in the default test
      run.
- **Incremental = fresh.** The existing randomized edit test runs over
  more of the files: several source files, more seeds, and edits drawn
  from the file itself. The fuzz test runs over arbitrary text.
- **Locality.** Tests assert the region a keystroke reads again, using
  the `regions` a change reports at layer 3:
  - A keystroke in a class's name reads only that name's token, plus its
    constructors.
  - A keystroke in a method's body reads at most that body's innermost
    statement.
  - A keystroke inside an identifier anywhere reads only that token.
  - Each assertion is shown to fail when the rule behind it is removed.
- **Recovery.** Cases of broken source:
  - each statement form with a missing `;`, `)` or `}`;
  - a stray `else`;
  - an unfinished expression;
  - a half-typed generic.
  - Each case states its diagnostics and the elements that still stand.
- **Performance.** `scale_test.dart` gains a keystroke into an
  identifier, into a statement and into a class name, each with the
  budget in requirement 11, and keeps the read of the largest file.

## Out of scope

- Resolving names to their declarations: scopes, references, imports.
  That belongs in a layer above, once this one stands.
- Types and type inference.
- Structural edits to Dart.
- Writing other syntaxes as Dart.
- Dart's experimental language features beyond Dart 3 as released.

## Decisions

1. **Names are elements of their own.** Each declared identifier is a
   one-token `name` element, and declarations no longer carry `name`.
   libara is not changed for this.
2. **The pairs stay** alongside the syntax elements.
3. **Patterns are read in full** in step 5.
4. **Types of more than one token are elements.**
5. **The corpus test runs by default**, so in CI too. It finds the
   `analyzer` package through this package's resolved dependencies, where
   it is a dev dependency, rather than through a path into the pub cache.

## Plan

Each step ends with what proves it done. Every step keeps the full suite,
the fuzz test and the randomized edit tests passing.

1. **Conformance harness.**
   - Write the analyzer-to-element mapping and the pre-order comparison.
     Run it against today's declarations only.
   - Add the corpus test over the `analyzer` package's `lib`.
   - *Verify:* today's declarations match on every file of this repo and
     libara.
2. **Names, enums, declarators, constructors.**
   - Add `name` elements and move `name` off the declarations, indexing
     `name` on them.
   - Add enum `value` elements, with enum members read as a class's are.
   - Make every declarator of a variable or field a name.
   - Apply the constructor rule, which reads the member alone and not
     its holder's name.
   - Add the inside-a-token rule to `affected`.
   - *Verify:* conformance on declarations, names and enum values. The
     locality test for a class rename reads one token (plus its
     constructors), and fails with the rule removed. A rename keystroke in
     a 1,500-line class costs under 1ms.
3. **Statements.**
   - Write the parser for bodies: blocks and every statement form, with
     each expression read as one opaque `expression` element for now.
   - Parse local variables and local functions.
   - Add the unit-that-reads-alone rule for statements and blocks.
   - *Verify:* conformance for statements on all files. Randomized edits
     match fresh reads. Recovery cases pass. A keystroke in a statement
     costs under 10ms at the 99th percentile.
4. **Expressions.**
   - Replace the opaque `expression` with full expressions: precedence,
     selectors, cascades, collections, closures, switch expressions, and
     the expressions inside interpolations.
   - Add formal parameters, type parameters, initializer lists,
     annotations and types.
   - *Verify:* conformance for expressions on all files, then on the
     `analyzer` corpus. Randomized edits and fuzz pass.
5. **Patterns.**
   - Add patterns in switch statements and expressions, `if`-`case`,
     pattern variable declarations and `for`-`in`.
   - *Verify:* conformance for patterns on all files and the corpus,
     including the analyzer's own pattern-heavy code.
6. **Performance and documentation.**
   - Run the scale tests with the budgets in requirement 11, profile, and
     fix what is over.
   - Update `doc/layers.md` and the format's documentation.
   - *Verify:* every timing test passes on a quiet machine. The docs
     describe every element kind.

Steps 1 and 2 stand on their own and deliver the local rename. Steps 3 to
5 build the parser up a layer at a time, so each can be reviewed and
committed before the next starts.

## Progress

- **Steps 1 and 2** are done. Typing in a class's name reads three tokens
  again, against 4,412 before. Typing in a name within a body reads that
  name and the elements that start or end at it, such as the expression
  it begins, since libara widens a region to take in an element that
  crosses its edge.
- **Step 3** is done, and goes beyond the plan in one respect: the body of
  a closure is already a `block` holding its statements, so that a
  keystroke within a test's closure reads again only the statements
  around it, rather than the whole `test(...)` call. The `closure` element
  itself comes in step 4.
  - Expressions are read only within bodies: those in field and variable
    initializers, default values, initializer lists and annotations wait
    for step 4.
  - What a `case` matches, its guard, and the pattern of a pattern
    variable declaration or of `for`-`in` wait for step 5.
  - While expressions are read whole, a missing `;` between two
    expression statements, as in `a = 1` before `b = 2;`, reads as one
    expression; it is found in step 4.
  - A keystroke reads again from the statement before the one it falls
    in, within its innermost block, to the first statement past it that
    ends where one ended before. Reading `lib/src/html/tree.dart` takes
    about 45ms, against 35ms before; a keystroke about 0.3ms.
- **Step 4** is done. Expressions are read wherever they stand: in
  bodies, in the values of fields and variables, in default values,
  initializer lists, annotations and enum values, and in interpolations.
  Formal parameters, type parameters, annotations, initializers and types
  of more than one token are elements of their own. On every file here,
  in libara and in the analyzer's `lib`, the elements agree with the
  analyzer's.
  - Four kinds the table above did not have are added: `instantiation`,
    `aware`, `strings` and `symbol`. A dot shorthand, as `.red`, is a
    `property` or a `call`, as the analyzer has it.
  - A cascade's `section` stands over the same tokens as what the section
    is, such as the `call` of `..add(1)`.
  - A `>>` or `>>>` is one token, so a type whose type arguments end with
    one ends with it, as the type around it does.
  - The pattern of a pattern assignment, as `(a, b) = (b, a)`, waits for
    step 5 with the others.
  - A diagnostic outside a body spans the declaration, as one in a body
    spans its statement. One that does not expect a name or a number
    says so by its kind, not its text: a keystroke within a name keeps
    what was read before, the diagnostic among it.
  - A keystroke in an expression outside any block reads its declaration
    again. Reading `lib/src/html/tree.dart` takes about 40ms; a keystroke
    about 0.45ms in the middle and 3.5ms at the tail.
- **Step 5** is done. Patterns are read in each `case` and its guard, in
  the arms of switch expressions, in `if`-`case`, in pattern variable
  declarations, in `for`-`in` and in pattern assignments, and agree with
  the analyzer's on every file here, in libara and in the analyzer's
  `lib`.
  - As with expressions, a pattern of one token is that token: `_`, a
    constant such as `1`, or a variable declared by its name alone, which
    is still a `name`.
  - A name alone in a pattern is a constant where the pattern matches,
    a variable where it declares, and nothing of its own where it
    assigns, as in `(a, b) = (b, a)`. So in `case Point(:x)`, `x` is a
    constant, as the analyzer has it.
  - A field with a name, `y: p` or `:p`, is an `argument`, as a named
    field of a record is; an entry of a map pattern is an `entry`.
  - In an arm of a switch expression, `(...) =>` after `when` ends the
    guard rather than starting a closure.
  - Reading `lib/src/html/tree.dart` takes about 45ms; a keystroke about
    0.3ms in the middle and 5ms at the tail.
- **Step 6** is done. `scale_test.dart` times typing in the name of a
  class 1,700 lines long and in a name within a body, each about 0.14ms
  in the middle, beside the read of the whole file, about 41ms, and a
  keystroke elsewhere, about 0.3ms in the middle and 5ms at the tail. All
  are within the budgets of requirement 11, so nothing needed profiling.
  The format's documentation names every element kind.
