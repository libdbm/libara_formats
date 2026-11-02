/// Markup syntaxes as libara grammars.
///
/// Each syntax is a libara `Format` from a text to a layered document: layer
/// 1 is the text, layer 2 its tokens and runs of text, and layer 3 the
/// elements paired from them. Nothing is taken out of the text, so a
/// document read in a syntax is written back in it character for character,
/// and what a syntax cannot write it refuses rather than approximates.
library;

export 'src/convert.dart' show Linked, Nested, structure;
export 'src/dart/dart.dart' show Dart;
export 'src/formats.dart' show Readable, Syntax, Writable, formats, importers;
export 'src/html/html.dart' show Foreign, HTML;
export 'src/json/json.dart' show JSON;
export 'src/kinds.dart' show Close, Comment, Empty, Open;
export 'src/latex/latex.dart' show LaTeX;
export 'src/lmnl/lmnl.dart' show LMNL;
export 'src/markdown/markdown.dart' show Markdown;
export 'src/roff/roff.dart' show Man, Me, Ms;
export 'src/rtf/rtf.dart' show RTF;
export 'src/xml/xml.dart' show XML;
