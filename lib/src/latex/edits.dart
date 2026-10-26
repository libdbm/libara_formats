part of 'latex.dart';

/// How LaTeX represents its elements, for its structural edits: see
/// `notation.dart`. An inline element is a command and its brace, an
/// environment a `\begin` and an `\end` on lines of their own, and a link
/// carries its address.
final class _LaTeX implements Notation {
  const _LaTeX();

  @override
  String get syntax => 'latex';

  /// What opens an element of [name] saying [said], where LaTeX represents it.
  static String? _opened(String name, Map<String, String> said) => name == 'a'
      ? '\\href{${_linked(said['href'] ?? '')}}{'
      : _notations[name]?.$1;

  /// What closes an element of [name], where anything does.
  static String? _closed(String name) => name == 'a'
      ? '}'
      : switch (_notations[name]?.$2) {
          '' => null,
          final closed => closed,
        };

  @override
  String? opening(String name, Map<String, String> said, String prefix) =>
      _opened(name, said);

  /// A break is two backslashes.
  @override
  String? empty(String name, Map<String, String> said, String prefix) =>
      name == 'br' ? r'\\' : null;

  @override
  String? closing(String name, Map<String, String> said, String prefix) =>
      _closed(name);

  @override
  String? wrapped(
    String name,
    Map<String, String> said,
    String words,
    String prefix,
  ) => switch (_opened(name, said)) {
    null => null,
    final opened => '$opened$words${_closed(name) ?? ''}',
  };

  /// An element's own command as another's, where both have one. A token
  /// leaves out the lines an environment's markup stands on, and a
  /// dollar opens and closes alike, so says neither.
  @override
  String? recast(
    String old,
    String name,
    Map<String, String> said,
    String words,
  ) {
    final (opened, closed) = (_opened(name, said), _closed(name));
    final open = old == 'a'
        ? words.startsWith(r'\href{')
        : words == _notations[old]?.$1.trim();
    final close = words == _closed(old)?.trim();
    if (open == close) {
      return null;
    }
    return open ? opened?.trim() : closed?.trim();
  }

  @override
  String prefix(Layered<int> document, int at) => '';

  @override
  String? lacking(String name, Map<String, String> said) => null;

  /// A break is one token, and has nothing to take away but itself.
  @override
  (String, Set<String>)? owns(String name) =>
      name == 'br' ? null : (name, {name});

  @override
  (Range, String)? listed(
    Layered<int> document,
    String name,
    Map<String, String> said,
    ARange range,
  ) => null;

  @override
  (Range, String)? unlisted(Layered<int> document, ARange element) => null;
}

/// How each element is represented, the link aside: what opens it and what
/// closes it.
const _notations = {
  'em': (r'\emph{', '}'),
  'strong': (r'\textbf{', '}'),
  'code': (r'\texttt{', '}'),
  'u': (r'\underline{', '}'),
  'sup': (r'\textsuperscript{', '}'),
  'sub': (r'\textsubscript{', '}'),
  'footnote': (r'\footnote{', '}'),
  'title': (r'\title{', '}'),
  'author': (r'\author{', '}'),
  'h1': (r'\section{', '}'),
  'h2': (r'\subsection{', '}'),
  'h3': (r'\subsubsection{', '}'),
  'h4': (r'\paragraph{', '}'),
  'h5': (r'\subparagraph{', '}'),
  // LaTeX has no sixth level, so the sixth is written as the fifth.
  'h6': (r'\subparagraph{', '}'),
  'ul': ('\\begin{itemize}\n', '\n\\end{itemize}'),
  'ol': ('\\begin{enumerate}\n', '\n\\end{enumerate}'),
  'dl': ('\\begin{description}\n', '\n\\end{description}'),
  'blockquote': ('\\begin{quote}\n', '\n\\end{quote}'),
  'abstract': ('\\begin{abstract}\n', '\n\\end{abstract}'),
  'pre': ('\\begin{verbatim}\n', '\n\\end{verbatim}'),
  'li': (r'\item ', ''),
  'math': (r'$', r'$'),
  'equation': (r'\[', r'\]'),
  'br': (r'\\', ''),
};

/// A link's address as a braced argument represents it: what would close the
/// argument, begin a command or end the paragraph is percent-encoded, as
/// an address may be, and what LaTeX reads as syntax is escaped.
String _linked(String href) => href
    .replaceAllMapped(
      _unsafe,
      (match) =>
          '%${match[0]!.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(2, '0')}',
    )
    .replaceAllMapped(_special, (match) => '\\${match[0]}');

/// What a braced argument cannot hold as it stands.
final _unsafe = RegExp(r'[{}\\\s]');

/// What LaTeX reads as syntax in an address.
final _special = RegExp('[#%&_~\$^]');
