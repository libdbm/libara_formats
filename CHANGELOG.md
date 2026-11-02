## 0.2.4

- RTF, as Word, LibreOffice, TextEdit and Pages write it: read into tokens
  and elements and written back byte for byte. It is read only: nothing
  is edited, and nothing else is written as RTF.
- `importers`, and the RTF importer: a file's content and elements in
  reading order as one normalized LMNL document, its revisions accepted,
  or kept as annotations.
- `Readable`, `Writable` and `Syntax`, which every format implements.
- The XML, HTML, Markdown, LaTeX and roff writers cut elements that cross
  so that they nest, blocks before inlines, where they refused them;
  XML marks the pieces with `part` and `join`. LMNL tells apart ranges of
  one name that cross by a suffix.

## 0.2.3

- Initial release: XML, HTML, Markdown, LMNL, man, ms, me, LaTeX, JSON
  and Dart as libara formats, versioned to match libara 0.2.3, whose
  `having` finds a Markdown link's definitions, and a Dart declaration by
  its name, without walking every token.
- Dart is read to its whole syntax: declarations, statements, expressions
  and patterns, each an element agreeing with the analyzer's parse on the
  analyzer's own source. A keystroke reads again only what it can change:
  typing in a name reads that name alone.
