part of 'roff.dart';

/// How a roff package represents its elements, for its structural edits: see
/// `notation.dart`. A face is a pair of escapes; a block a request line
/// and, for a container, the request that closes it, each on a line of its
/// own.
final class _Roff implements Notation {
  const _Roff(this.syntax, this.notations);

  @override
  final String syntax;

  /// How the package represents each element it can, the faces aside: what
  /// opens it and what closes it, nothing where a request that follows
  /// closes it.
  final Map<String, (String, String)> notations;

  (String, String)? _notation(String name) => _faces[name] ?? notations[name];

  @override
  String? opening(String name, Map<String, String> said, String prefix) {
    final held = _notation(name);
    if (held == null) {
      return null;
    }
    final (opened, _) = held;
    if (!opened.startsWith('.')) {
      return opened;
    }
    if (name == 'a') {
      final href = said['href'];
      return href == null ? null : '$prefix$opened$href\n';
    }
    return '$prefix$opened';
  }

  /// A break is a request on a line of its own.
  @override
  String? empty(String name, Map<String, String> said, String prefix) =>
      name == 'br' ? '$prefix.br\n' : null;

  @override
  String? closing(String name, Map<String, String> said, String prefix) {
    final held = _notation(name);
    if (held == null || held.$2.isEmpty) {
      return null;
    }
    final (_, closed) = held;
    return closed.startsWith('.') ? '$prefix$closed' : closed;
  }

  @override
  String? wrapped(
    String name,
    Map<String, String> said,
    String words,
    String prefix,
  ) {
    final opened = opening(name, said, prefix);
    if (opened == null) {
      return null;
    }
    final closed = _notation(name)!.$2;
    if (closed.isEmpty) {
      return '$opened$words';
    }
    if (!closed.startsWith('.')) {
      return '$opened$words$closed';
    }
    // Words that stop short of their line's end close on a line of their
    // own that the line's end ends.
    return words.endsWith('\n')
        ? '$opened$words$closed'
        : '$opened$words\n${closed.substring(0, closed.length - 1)}';
  }

  /// A face's or a block's own markup as the other's, where both have
  /// one; a closing face escape stays, since `\fP` closes any face.
  @override
  String? recast(
    String old,
    String name,
    Map<String, String> said,
    String words,
  ) {
    final (was, now) = (_notation(old), _notation(name));
    if (was == null || now == null) {
      return null;
    }
    if (words == was.$1 && now.$1.isNotEmpty && name != 'a') {
      return now.$1;
    }
    if (words == was.$2 && now.$2.isNotEmpty) {
      return now.$2;
    }
    if (_faces.containsKey(old) && _faces.containsKey(name)) {
      return words;
    }
    return null;
  }

  /// Nothing where [at] begins a line, and otherwise a line ending, since a
  /// request stands at the head of a line.
  @override
  String prefix(Layered<int> document, int at) =>
      at == 0 || covered(document, span(at - 1, 1)) == '\n' ? '' : '\n';

  @override
  String? lacking(String name, Map<String, String> said) => null;

  /// A page's title and a break are one token and have nothing to take
  /// away but themselves.
  @override
  (String, Set<String>)? owns(String name) =>
      name == 'head' || name == 'br' ? null : (name, {name});

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

/// The faces, written the same in every package.
const _faces = {
  'strong': (r'\fB', r'\fP'),
  'em': (r'\fI', r'\fP'),
  'code': (r'\fC', r'\fP'),
};
