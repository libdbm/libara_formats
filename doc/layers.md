# How each syntax maps onto libara's layers

Every syntax here is a libara `Format` from a text to a `Layered<int>`
document of three layers:

1. **The text**, as it was read, every character kept. Writing a document
   back in the syntax it was read in gives this text, byte for byte.
2. **Tokens.** Ranges over the text that tile it: every character belongs
   to exactly one token. A token that is markup is named for what it
   represents, under the empty key: Markdown's `*` on either side of a word,
   roff's `\fI` and `\fP`, LaTeX's `\emph{` and its `}`, and XML's `<em>`
   and `</em>` are all called `em`. The rest is runs of `#text`. A token
   that stands for a character, such as a reference or an escape, says
   what it stands for as `shows`.
3. **Elements.** Ranges over layer 2's tokens, each carrying what its
   markup says as attributes. The document itself is not a range: it is
   the whole of the layer.

Every syntax names its elements from one shared vocabulary, so that a
paragraph is a `p`, a second-level heading an `h2` and emphasis an `em`
whichever syntax it was read in. That is what lets a document read in one
syntax be written in another. The names are taken from HTML where HTML has
one; a construct HTML lacks, such as a roff equation or a LaTeX
footnote, keeps a name of its own.

Nothing derived is stored. Which token opens an element and which closes
it, which element holds which, and what the reader is shown are all read
off the layers when they are asked for. An element represented by no markup
of its own, such as a paragraph in Markdown, a paragraph no request opened
in roff or an implied `body` in HTML, is a range over the tokens it holds,
with no tokens of its own.

What a reading finds wrong is a diagnostic, a range on the layer it was
found at, and the document is still read. What would cost more than
libara's `Limits` allow is refused with `Kind.invalid` before it is built.

## After an edit

An edit at layer 1 is a keystroke. libara asks the syntax what stretch to
read again, then reads only that stretch and keeps every range outside it.

- **XML, HTML and LMNL** read a token from its own start, so a keystroke
  reads again only the tokens it touches, and the elements are read again
  where a tag changes.
- **Markdown, roff and LaTeX** read a line by what the lines before it say.
  A keystroke reads again from a boundary before it to the first boundary
  past it where the new reading has nothing open. A boundary is a place no
  element spans: in Markdown a line after a blank line, in roff a paragraph
  request or a heading, in LaTeX a line after a blank line. Where a change
  could alter what every later line means, such as a `delim` in roff or the
  beginning of a LaTeX document, the whole text is read again.
- **JSON** reads a token from its own start, a string whole from its
  quote, so a keystroke reads again only the tokens it touches. Its values
  are read again over the innermost array or object around it that still
  closes where it did.
- **Dart** has strings and comments that hold line breaks, and strings
  within the interpolations of strings, so each token within a string
  says what is open where it starts. A keystroke reads again from the
  tokens before it, with what they say is open, to the first token past
  it that says what the new reading has open there. Where every token a
  keystroke changes is of the kind it was, as typing in a name is, only
  the names over them are read again. Where a keystroke opens or closes
  nothing, its pairs stand, and its declarations are read
  again from the declaration it falls in to the first past it that ends
  where one ended before; otherwise over the innermost pair around it that
  still closes where it did, or the declaration that pair is part of.

An edit at layer 2 or 3 is structural: it marks, unmarks, renames or
deletes. Each syntax carries it out as text written or taken away one layer
down, so the layers after it are the layers a fresh read of the new text
gives. A syntax refuses, with `Kind.invalid` and a reason, what it has no
representation for, and in XML and HTML what would not nest.

## XML

- **Tokens.** One per tag, comment, processing instruction, declaration,
  CDATA section and entity reference, and one per run of text between
  them. A tag says its attributes under their names. The others take the
  DOM's names: `#text`, `#comment`, `#pi`, `#doctype`, `#declaration`,
  `#cdata` and `#entity`, the last two saying what they stand for as
  `shows`.
- **Elements.** Each runs from its start tag to its end tag, or is its one
  empty tag, and carries the start tag's name and attributes. A tag that
  does not pair is a diagnostic.

## HTML

- **Tokens.** As the WHATWG standard tokenizes: one per tag, comment,
  doctype and character reference, names lower-cased and references in
  attribute values resolved. Markup the standard reads and drops is
  `#bogus`. An element the standard does not read as markup inside, such
  as `script`, `style`, `title` or `textarea`, is one token from its start
  tag through its end tag.
- **Elements.** The standard's tree construction, run over the tokens: the
  implied `html`, `head` and `body`, the elements closed for you, and the
  adoption agency's clones are all elements. The standard's parse errors
  are diagnostics. Elements can tie or be empty, so which holds which is
  read from the tree, built again.

## LMNL

- **Tokens.** One per tag (`[name}` opens, `{name]` closes and `[name]`
  is an empty range), atom `{{name}}`, comment `[!-- --]` and escape `\x`,
  and one per run of text. A tag's annotations, `[l [n}144{n]}`, are
  attributes holding the text they were written as.
- **Elements.** An end tag closes the latest open start tag of its name
  and suffix, `[a=1}` closing at `{a=1]`, so elements may overlap, which
  is what LMNL is for. A tag that pairs with nothing is a diagnostic. An
  element says what its start tag says, and what its end tag says
  besides. An empty range and an atom are each an element
  over its one tag.

## Markdown

- **Tokens.** Each mark that is syntax is a token named for the block or
  inline it belongs to: a heading's hashes, a quote's angle on every
  line, an item's bullet and the indent that carries it on, a fence, a
  rule, a pipe table's bars and dashes, and each inline's marks, such as
  `*` for `em`. The rest is `#text`, cut where a block starts or ends.
- **Elements.** CommonMark's blocks and inlines under the shared names: `p`,
  `h1` to `h6`, `blockquote`, `ul`, `ol`, `li`, `pre`, `hr`, `table`,
  `tr`, `th`, `td`, `em`, `strong`, `code`, `a`, `img` and `br`. A
  paragraph, a list and an item's words have no tokens of their own. A
  link titled `element` stands for an element of the name it points to,
  which is how Markdown writes what it cannot otherwise represent.

## man, ms and me

The three roff packages share one grammar, each with its own table of what
its requests open.

- **Tokens.** Each request line, escape and quote that is syntax is a token
  named for the element it represents. A request the package does not know is
  `#pi`, showing nothing, so a page round-trips without the request being
  run. A comment is `#comment`, and an escape is `#escape` saying what it
  shows, a string `\*` uses showing what `.ds` or `.as` defined it as. The
  rest is `#text`.
- **Elements.** From the first token of each to its last: headings,
  paragraphs, terms and items, displays, links, faces set by `\f` escapes
  and font requests, eqn equations, saying `notation` as `eqn`, and tbl
  tables as `table`, `tr` and `td`, each cell's faces closing with it. A
  pic picture is a `pre` of class `picture`, read as it stands. A
  paragraph no request opened is a `p` saying `implied`.

## LaTeX

- **Tokens.** Each command, brace and dollar that represents an element is a
  token named for it. An escape, or a command showing what it shows, is an
  `#escape`; a comment is a `#comment`, as are a `comment` environment and
  what stands between `\iffalse` and its `\fi`; the rest is `#text`. Only
  a command defined with no arguments as words alone is expanded, showing
  those words where it is used: any other command the tables do not know
  is an element of its own name over its braced arguments.
- **Elements.** Sections, lists, environments, inline commands and
  declarations, mathematics, links, pictures and a bibliography, under
  the shared names. A `\label` is an anchor `a` saying its key as `id`,
  and a `\ref` a link to it. acmart's front matter is read as what it is:
  an affiliation an `address` of `span`s, an email a link, an author's
  note a footnote, and keywords and classifications a `div` each; its
  publication data, such as `\acmDOI`, shows nothing. A paragraph is a `p`
  saying `implied`. The preamble and the document are elements, and only
  the title and author in the preamble show.

## JSON

- **Tokens.** Each of `{`, `}`, `[`, `]`, `:` and `,` is a token named for
  itself, and each run of whitespace is a `#space`. A string, from its
  quote to its quote, is a `#string` saying its characters, escape
  sequences decoded, as `shows`; one that no quote closes ends at its line
  break. A number is a `#number` and `true`, `false` and `null` a
  `#literal`, each saying what it shows. What does not scan is an
  `#error`.
- **Values.** Each `object`, `array`, `string`, `number`, `boolean` and
  `null` over its tokens, and each `member` of an object from its name to
  its value, saying its name, decoded, as `key`. An array or object that
  nothing closes is a diagnostic, and still a value up to the mark that
  closes what holds it.
- **Edits.** Only strings are text, so a text edit elsewhere, or one
  that would end a string or start another, is not valid, and structural
  edits are refused. JSON writes only a document read as JSON.

## Dart

- **Tokens.** As Dart's own scanner reads them, which the tests check on
  every source file here: each word a `#keyword` or a `#name`, each
  number a `#number`, each operator and mark named for itself, and each
  comment a `#comment`. A string is its quotes, named for themselves with
  `r` where it is raw, its runs of characters, `#text`, its escape
  sequences, `#escape`, and its interpolations, `$` and a name or `${`,
  code and `}`. A token within a string says under `in` which strings and
  interpolations are open where it starts.
- **Pairs.** `parens`, `brackets`, `braces`, `string` and
  `interpolation`, each over its tokens from its opening mark to its
  closing one. What does not pair is a diagnostic.
- **Declarations.** Also in layer 3, at the top level and in the body of
  each class, mixin, extension and enum: each named for its kind, such as
  `class`, `function`, `method`, `constructor`, `getter`, `field` or an
  enum's `value`. Each name declared is a `name` of its own, saying the
  name as `name`, which is indexed so that libara's `having` finds every
  declared name without walking the tokens. The tests check them against
  the analyzer's parser on every source file here and on the analyzer's
  own.
- **Statements.** Also in layer 3, in the body of each function, method,
  constructor, getter and setter, local functions and closures included:
  each `block`, each statement named for its kind, such as `if`, `for`,
  `switch`, `case`, `try`, `catch`, `return` or `variable`, and an
  expression statement a `statement`. What does not read as a statement
  should, such as a missing `;`, is a diagnostic. A keystroke reads again
  only the statements around it in its innermost block.
- **Expressions.** Also in layer 3, wherever one stands: each of more
  than one token named for its kind, such as `assignment`, `binary` with
  its `operator`, `call`, `property`, `index`, `cascade` with a `section`
  for each `..`, `closure`, `list`, `map` or `switch`, with Dart's
  precedence. Each type of more than one token is a `type`, and each
  formal parameter, type parameter, annotation and constructor
  initializer a `parameter`, `generic`, `annotation` or `initializer`.
  The tests check them against the analyzer's parser as they do the
  declarations. A keystroke in an expression outside any block reads its
  declaration again.
- **Patterns.** Also in layer 3, wherever Dart takes one: each of more
  than one token a `pattern` saying its `form`, such as `object`,
  `record`, `list`, `variable` or `logical`, and each variable it
  declares a `name`.
- **Edits.** Only the characters of strings and comments are text,
  structural edits are refused, and Dart writes only a document read as
  Dart.

## Writing in another syntax

`encode` writes a document in a syntax other than the one it was read in
by projecting it onto its content: a `#text` token gives its text, a token
that `shows` something gives that, and other markup gives nothing. Each
element is placed over the content it covers, in the order its source
nests them, and written as the target represents it. XML and HTML refuse
elements that overlap. What a target has no representation for, such as a
picture in roff, is refused with a reason.
