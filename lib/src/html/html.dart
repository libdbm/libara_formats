import 'dart:math';

import 'package:libara/libara.dart';

import '../convert.dart';
import '../editing.dart';
import '../formats.dart';
import '../kinds.dart';
import 'legacy.dart';
import '../lexing.dart';
import '../limits.dart';
import '../named.dart';
import '../safety.dart';
import '../tags.dart' show opener;
import '../tags.dart' as tags show escaped;

part 'edits.dart';
part 'foreign.dart';
part 'tree.dart';

/// HTML, tokenized as the WHATWG standard tokenizes it.
///
/// Layer 2 holds one token per tag, comment, doctype and character
/// reference, and one per run of text between them:
/// - Tag and attribute names are lower-cased. An attribute's value says what
///   it reads as, its references resolved. A repeated attribute is dropped,
///   the first one kept.
/// - Comments and bogus comments are `#comment`, the doctype `#doctype`, and
///   a reference `#entity` with a `shows` attribute.
/// - Markup the standard reads and drops, such as `</>` or a tag the text
///   ends inside, is `#bogus`.
/// - An element whose content the standard does not read as markup, such as
///   `script`, `style`, `title` and `textarea`, is one token from its start
///   tag through its end tag, so every token can still be read from its own
///   start. `plaintext` takes in the rest of the text.
///
/// The standard's parse errors are diagnostics. Scripting is taken to be
/// on, as in a browser and in `package:html`, so `noscript` holds text.
/// Not followed: the escapes inside a script, where `<!--` changes what
/// ends it.
final class HTML implements Syntax {
  /// The HTML syntax, reading within [limits].
  const HTML({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      decoded('html', _Grammar(limits), limits, form);

  /// [value]'s text, where it was read as HTML, and otherwise its content
  /// in its elements, which must nest: a void element has no end tag, what
  /// HTML reads as it stands is written so, and nothing a browser would run
  /// is written at all.
  @override
  Result<Sequence<int>> encode(Layered<int> value) => value.grammar is _Grammar
      ? Success(value.items)
      : tree(
          value,
          'html',
          empty: (name) => _voids.contains(name) ? '>' : '></$name>',
          verbatim: _raw,
          safe: true,
        );
}

final class _Grammar implements Grammar<int>, Nesting {
  const _Grammar(this.limits);

  final Limits limits;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) {
    if (layer == 2) {
      return tokens(document, region, limits, _next);
    }
    // Less than the whole layer is asked for only where [affected] found
    // that nothing in it changes, so what stands there is what derives.
    if (region.start > 0 || document.span(2, span(region.end, 1)).isNotEmpty) {
      return (
        ranges: [
          for (final (_, element) in document.within(3, region)) element,
        ],
        diagnostics: [
          for (final problem in document.diagnostics(3).items.cast<ARange>())
            if (region.start <= problem.start && problem.end <= region.end)
              problem,
        ],
      );
    }
    final (elements, problems) = _Builder(
      document,
      deepest: limits.depth,
    ).run();
    return (
      ranges: [for (final (element, _, _) in elements) element],
      diagnostics: problems,
    );
  }

  /// At layer 2, as every syntax's tokens are read again. At layer 3, the
  /// change alone where an edit of the text changed nothing the tree is
  /// built from: see [_quiet]. Every token otherwise, since the tree a
  /// token makes depends on all that came before it.
  @override
  Range affected(Layered<int> document, int layer, Range changed) {
    if (layer == 2) {
      return relexed(document, changed, _next);
    }
    return _quiet(document, changed)
        ? changed
        : span(0, document.layer(2).length);
  }

  /// Whether the edit that made [document] changed only text the tree does
  /// not depend on, at the [changed] tokens:
  /// - one edit of the text replaced runs of text, and references, with
  ///   runs of text and references, neither side empty;
  /// - space alone, and text saying nothing but space and NULs, stay so;
  /// - no element starts or ends at a changed token, and no diagnostic
  ///   touches one;
  /// - the innermost elements around them are none of `html`, `head`, a
  ///   table part, `colgroup` or `frameset`, where text changes the tree.
  bool _quiet(Layered<int> document, Range changed) {
    final before = document.previous;
    final edits = document.changes;
    if (before == null ||
        edits.length != 1 ||
        edits.single.layer != 1 ||
        changed.length == 0) {
      return false;
    }
    final now = [for (final (_, token) in document.span(2, changed)) token];
    if (!now.every(_texty)) {
      return false;
    }
    final (cut, put) = switch (edits.single.command) {
      Insert(:final items) => (0, items.length),
      Delete(span: final gone) => (gone.length, 0),
      Replace(span: final gone, :final items) => (gone.length, items.length),
      _ => (-1, -1),
    };
    if (cut < 0) {
      return false;
    }
    final from = now.first.start;
    final to = now.last.end - put + cut;
    if (to <= from) {
      return false;
    }
    final old = [
      for (final (_, token) in before.within(2, span(from, to - from))) token,
    ];
    if (old.isEmpty ||
        old.first.start != from ||
        old.last.end != to ||
        !old.every(_texty) ||
        _spaced(before, old) != _spaced(document, now) ||
        _said(before, old) != _said(document, now)) {
      return false;
    }
    // Before as well as after, since an element that ended at a token the
    // edit joined into another has already been shrunk off it.
    final low = changed.start;
    if (_anchored(document, low, changed.end) ||
        _anchored(before, low, low + old.length)) {
      return false;
    }
    final high = changed.end;
    final around = [
      for (final (_, element) in document.crossing(3, low))
        if (element.end > high) element,
    ];
    if (around.isEmpty) {
      return false;
    }
    final least = around.map((element) => element.length).reduce(min);
    return !around.any(
      (element) =>
          element.length == least &&
          const {
            'html', 'head', 'table', 'tbody', 'thead', 'tfoot', 'tr', //
            'colgroup', 'frameset',
          }.contains('${element.get('')}'),
    );
  }

  /// Whether an element of [document] starts or ends, or a diagnostic
  /// touches, between tokens [low] and [high].
  static bool _anchored(Layered<int> document, int low, int high) {
    for (final (_, element) in [
      ...document.crossing(3, low),
      ...document.crossing(3, high),
      ...document.within(3, span(low, high - low)),
    ]) {
      if ((low <= element.start && element.start <= high) ||
          (low <= element.end && element.end <= high)) {
        return true;
      }
    }
    return document
        .diagnostics(3)
        .items
        .any((problem) => problem.start <= high && low <= problem.end);
  }

  /// Whether [token] is a run of text or a reference.
  static bool _texty(ARange token) {
    final name = '${token.get('')}';
    return name == prose || name == '#entity';
  }

  /// What [tokens], runs of text and references, say.
  static String _spoken(Layered<int> document, List<ARange> tokens) => [
    for (final token in tokens)
      '${token.get('')}' == prose
          ? String.fromCharCodes(document.slice(token).items)
          : '${token.get('shows')}',
  ].join();

  /// Whether [tokens] say nothing but space.
  static bool _spaced(Layered<int> document, List<ARange> tokens) =>
      _spoken(document, tokens).trim().isEmpty;

  /// Whether [tokens] say something besides space and NULs.
  static bool _said(Layered<int> document, List<ARange> tokens) =>
      _spoken(document, tokens).replaceAll('\u0000', '').trim().isNotEmpty;

  /// As the tree construction nests them: see [nested].
  @override
  List<(ARange, int)> nesting(Layered<int> document) => [
    for (final (element, depth, _) in nested(document)) (element, depth),
  ];

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      _edit(document, change);

  /// What [change] makes of [document] where it leaves the markup as it
  /// stands.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      checked(document, change, 'html', tags: true);

  /// [text] as words alone, escaped where this syntax would read markup.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) =>
      escaping(text, tags.escaped, raw: raw);

  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      crossed(document, layer, range);
}

/// The token starting at [at] in [text].
Token _next(String text, int at) {
  final unit = text.codeUnitAt(at);
  if (unit == _less) {
    if (_markup(text, at) case final token?) {
      return token;
    }
  } else if (unit == _amp) {
    if (_reference(text, at, attribute: false) case (
      final end,
      final shows,
      final problem,
    )) {
      return (end, '#entity', {'shows': literal(shows)}, problem);
    }
  }
  var stop = at + 1;
  while (stop < text.length) {
    final next = text.codeUnitAt(stop);
    if (next == _less && _opens(text, stop)) {
      break;
    }
    if (next == _amp && _reference(text, stop, attribute: false) != null) {
      break;
    }
    stop++;
  }
  return (stop, prose, const {}, null);
}

/// Whether the `<` at [at] opens markup rather than standing as text: a
/// letter, `!` or `?` follows it, or `/` and something more.
bool _opens(String text, int at) {
  if (at + 1 >= text.length) {
    return false;
  }
  final next = text.codeUnitAt(at + 1);
  return _letter(next) ||
      next == _bang ||
      next == _question ||
      (next == _slash && at + 2 < text.length);
}

/// The markup opening with the `<` at [at], or null where it is text.
Token? _markup(String text, int at) {
  if (!_opens(text, at)) {
    return null;
  }
  final next = text.codeUnitAt(at + 1);
  if (_letter(next)) {
    return _tag(text, at, closing: false);
  }
  if (next == _slash) {
    final after = text.codeUnitAt(at + 2);
    if (_letter(after)) {
      return _tag(text, at, closing: true);
    }
    if (after == _greater) {
      return (at + 3, '#bogus', const {}, 'missing end tag name');
    }
    return _bogus(text, at, 2);
  }
  if (next == _question) {
    return _instruction(text, at);
  }
  if (text.startsWith('<![CDATA[', at)) {
    // Read to its own end everywhere: text in foreign content, and a
    // comment, as the standard has it, outside it.
    final close = text.indexOf(']]>', at + 9);
    return close < 0
        ? (
            text.length,
            '#cdata',
            {'shows': literal(text.substring(at + 9))},
            'end of text in a CDATA section',
          )
        : (
            close + 3,
            '#cdata',
            {'shows': literal(text.substring(at + 9, close))},
            null,
          );
  }
  if (text.startsWith('<!--', at)) {
    return _comment(text, at);
  }
  if (text.length >= at + 9 &&
      text.substring(at + 2, at + 9).toLowerCase() == 'doctype') {
    final close = text.indexOf('>', at + 9);
    return close < 0
        ? (text.length, '#doctype', const {}, 'end of text in a doctype')
        : (close + 1, '#doctype', const {}, null);
  }
  return _bogus(text, at, 2);
}

/// The processing instruction opening `<?` at [at]: a target of letters,
/// digits, `-` and `_`, starting with a letter or `_`, then its data to the
/// first `>`. A target of `xml` or `xml-stylesheet`, or one that is not a
/// target, makes the bogus comment the standard makes of it, and one the
/// text ends inside is dropped.
Token _instruction(String text, int at) {
  final length = text.length;
  const dropped = 'end of text in a processing instruction';
  if (at + 2 >= length) {
    return (length, '#bogus', const {}, dropped);
  }
  final first = text.codeUnitAt(at + 2);
  if (!_letter(first) && first != _underscore) {
    return _bogus(text, at, 2);
  }
  var index = at + 2;
  while (index < length) {
    final unit = text.codeUnitAt(index);
    if (!_alnum(unit) && unit != _hyphen && unit != _underscore) {
      break;
    }
    index++;
  }
  if (index >= length) {
    return (length, '#bogus', const {}, dropped);
  }
  final unit = text.codeUnitAt(index);
  final target = text.substring(at + 2, index).toLowerCase();
  if (!(_space(unit) || unit == _question || unit == _greater) ||
      target == 'xml' ||
      target == 'xml-stylesheet') {
    return _bogus(text, at, 2);
  }
  final close = text.indexOf('>', index);
  return close < 0
      ? (length, '#bogus', const {}, dropped)
      : (close + 1, '#pi', const {}, null);
}

/// A comment the standard makes of markup that is not one, from [at] to
/// the first `>` past [skip] characters, or to the end of the text.
Token _bogus(String text, int at, int skip) {
  final close = text.indexOf('>', at + skip);
  return (
    close < 0 ? text.length : close + 1,
    '#comment',
    const {},
    'bogus comment',
  );
}

/// The comment opening `<!--` at [at], closed by `-->` or `--!>`, or at
/// once by `<!-->` and `<!--->`.
Token _comment(String text, int at) {
  if (text.startsWith('>', at + 4)) {
    return (at + 5, '#comment', const {}, 'abrupt closing of empty comment');
  }
  if (text.startsWith('->', at + 4)) {
    return (at + 6, '#comment', const {}, 'abrupt closing of empty comment');
  }
  var dashes = text.indexOf('--', at + 4);
  while (dashes >= 0) {
    if (text.startsWith('>', dashes + 2)) {
      return (dashes + 3, '#comment', const {}, null);
    }
    if (text.startsWith('!>', dashes + 2)) {
      return (dashes + 4, '#comment', const {}, 'incorrectly closed comment');
    }
    dashes = text.indexOf('--', dashes + 1);
  }
  return (text.length, '#comment', const {}, 'end of text in a comment');
}

/// The tag opening at [at], an end tag where [closing], read as the
/// standard reads it; and for an element whose content is not markup, that
/// content and its end tag with it.
Token _tag(String text, int at, {required bool closing}) =>
    _scanned(text, at, closing: closing).$1;

/// Whether the start tag [text] closes itself, as the standard reads it:
/// `<a b=c/>` does not, its `/` being part of the value.
bool selfClosed(String text) => _scanned(text, 0, closing: false).$2;

/// The tag at [at], and whether it closes itself.
(Token, bool) _scanned(String text, int at, {required bool closing}) {
  final length = text.length;
  var index = at + (closing ? 2 : 1);
  final start = index;
  while (index < length && !_ends(text.codeUnitAt(index))) {
    index++;
  }
  final name = _named(text.substring(start, index));
  final attributes = <String, Value>{};
  String? problem;
  var closed = false;
  while (true) {
    while (index < length && _space(text.codeUnitAt(index))) {
      index++;
    }
    if (index >= length) {
      return ((length, '#bogus', const {}, 'end of text in a tag'), false);
    }
    final unit = text.codeUnitAt(index);
    if (unit == _greater) {
      index++;
      break;
    }
    if (unit == _slash) {
      index++;
      if (index < length && text.codeUnitAt(index) == _greater) {
        index++;
        closed = true;
        break;
      }
      continue;
    }
    final from = index;
    index++;
    while (index < length) {
      final next = text.codeUnitAt(index);
      if (_ends(next) || next == _equals) {
        break;
      }
      index++;
    }
    final key = _named(text.substring(from, index));
    while (index < length && _space(text.codeUnitAt(index))) {
      index++;
    }
    var written = '';
    if (index < length && text.codeUnitAt(index) == _equals) {
      index++;
      while (index < length && _space(text.codeUnitAt(index))) {
        index++;
      }
      if (index >= length) {
        return ((length, '#bogus', const {}, 'end of text in a tag'), false);
      }
      final quote = text.codeUnitAt(index);
      if (quote == _double || quote == _single) {
        final close = text.indexOf(String.fromCharCode(quote), index + 1);
        if (close < 0) {
          return ((length, '#bogus', const {}, 'end of text in a tag'), false);
        }
        written = text.substring(index + 1, close);
        index = close + 1;
      } else if (quote != _greater) {
        final from = index;
        while (index < length &&
            !_space(text.codeUnitAt(index)) &&
            text.codeUnitAt(index) != _greater) {
          index++;
        }
        written = text.substring(from, index);
      }
    }
    if (attributes.containsKey(key) || key.isEmpty) {
      problem = 'duplicate attribute $key';
    } else {
      attributes[key] = literal(
        _decoded(written).replaceAll('\u0000', '\uFFFD'),
      );
    }
  }
  if (closing) {
    return (
      (
        index,
        name,
        const <String, Value>{},
        attributes.isEmpty ? problem : 'end tag with attributes',
      ),
      false,
    );
  }
  if (name == 'plaintext') {
    return ((length, name, attributes, problem), closed);
  }
  if (name == 'script') {
    return ((_script(text, index), name, attributes, problem), closed);
  }
  if (_raw.contains(name)) {
    return ((_content(text, index, name), name, attributes, problem), closed);
  }
  return ((index, name, attributes, problem), closed);
}

/// A tag or attribute name as the standard reads it: lower-cased, a NUL
/// read as U+FFFD.
String _named(String text) => _lower(text).replaceAll('\u0000', '\uFFFD');

/// Where the content of a [name] element from [from] ends with its end
/// tag, or the end of the text: the first `</name` followed by a space, a
/// slash or `>`, in any case, read to its own close.
int _content(String text, int from, String name) {
  var at = text.indexOf('</', from);
  while (at >= 0) {
    final after = at + 2 + name.length;
    if (after < text.length &&
        _lower(text.substring(at + 2, after)) == name &&
        _ends(text.codeUnitAt(after))) {
      final (end, _, _, _) = _tag(text, at, closing: true);
      return end;
    }
    at = text.indexOf('</', at + 2);
  }
  return text.length;
}

/// What the doctype [text], a `#doctype` token, says, as the standard's
/// tokenizer reads it: its name, public and system identifiers, and whether
/// it is well formed, which a doctype that sets force-quirks is not.
({String? name, String? public, String? system, bool correct}) doctype(
  String text,
) {
  final length = text.endsWith('>') ? text.length - 1 : text.length;
  final ended = text.endsWith('>');
  var at = 9;
  String? name;
  String? public;
  String? system;
  var correct = true;
  bool space() =>
      at < length &&
      const {0x20, 0x09, 0x0A, 0x0C, 0x0D}.contains(text.codeUnitAt(at));
  void skip() {
    while (space()) {
      at++;
    }
  }

  ({String? name, String? public, String? system, bool correct}) done() =>
      (name: name, public: public, system: system, correct: correct);

  // An identifier quoted from [at], to its quote or to an early `>`, which
  // is abrupt and spoils the doctype, or the end, which does too.
  String quoted() {
    final quote = text[at];
    at++;
    final start = at;
    while (at < length && text[at] != quote) {
      at++;
    }
    final found = text.substring(start, at).replaceAll('\u0000', '\uFFFD');
    if (at >= length) {
      correct = false;
    } else {
      at++;
    }
    return found;
  }

  bool quote() => at < length && (text[at] == '"' || text[at] == "'");

  skip();
  if (at >= length) {
    return (name: null, public: null, system: null, correct: false);
  }
  final start = at;
  while (at < length && !space()) {
    at++;
  }
  name = _lower(text.substring(start, at)).replaceAll('\u0000', '\uFFFD');
  if (!ended && at >= length) {
    correct = false;
    return done();
  }
  skip();
  if (at >= length) {
    correct = ended && correct;
    return done();
  }
  final keyword = at + 6 <= length
      ? text.substring(at, at + 6).toUpperCase()
      : '';
  if (keyword != 'PUBLIC' && keyword != 'SYSTEM') {
    correct = false;
    return done();
  }
  at += 6;
  skip();
  if (!quote()) {
    correct = false;
    return done();
  }
  if (keyword == 'PUBLIC') {
    public = quoted();
    if (!correct) {
      return done();
    }
    skip();
    if (quote()) {
      system = quoted();
    } else if (at < length) {
      correct = false;
      return done();
    }
  } else {
    system = quoted();
  }
  if (!correct) {
    return done();
  }
  // Anything after the identifiers makes a bogus doctype, which stays well
  // formed even where the text ends inside it.
  skip();
  if (at >= length && !ended) {
    correct = false;
  }
  return done();
}

/// Where a script's content from [from] ends with its end tag, or the end
/// of the text, through the standard's escapes: after `<!--` a `<script`
/// opens a stretch in which `</script` does not end the script, closed by
/// `</script` again or by `-->`.
int _script(String text, int from) {
  var escaped = false;
  var doubled = false;
  var at = from;
  while (at < text.length) {
    if (text.startsWith('-->', at)) {
      escaped = false;
      doubled = false;
      at += 3;
      continue;
    }
    if (!escaped && text.startsWith('<!--', at)) {
      escaped = true;
      at += 4;
      continue;
    }
    if (text.codeUnitAt(at) == _less) {
      final closing = at + 1 < text.length && text.codeUnitAt(at + 1) == _slash;
      final name = at + (closing ? 2 : 1);
      final after = name + 6;
      if (after < text.length &&
          _lower(text.substring(name, after)) == 'script' &&
          _ends(text.codeUnitAt(after))) {
        if (closing && !doubled) {
          final (end, _, _, _) = _tag(text, at, closing: true);
          return end;
        }
        if (escaped) {
          doubled = !closing;
        }
        at = after;
        continue;
      }
    }
    at++;
  }
  return text.length;
}

/// The character reference at the `&` at [at]: where it ends, what it
/// stands for, and what is wrong with how it is written; or null where the
/// `&` is text. In an [attribute], a legacy name without its semicolon
/// before `=` or a letter or digit is text, as the standard has it.
(int, String, String?)? _reference(
  String text,
  int at, {
  required bool attribute,
}) {
  if (at + 1 >= text.length) {
    return null;
  }
  final first = text.codeUnitAt(at + 1);
  if (first == _hash) {
    var index = at + 2;
    final hex = index < text.length && (text.codeUnitAt(index) | 0x20) == 0x78;
    if (hex) {
      index++;
    }
    final from = index;
    var value = 0;
    while (index < text.length) {
      final digit = _digit(text.codeUnitAt(index), hex);
      if (digit < 0) {
        break;
      }
      value = value > 0x10FFFF ? value : value * (hex ? 16 : 10) + digit;
      index++;
    }
    if (index == from) {
      return null;
    }
    if (index < text.length && text.codeUnitAt(index) == _semicolon) {
      return (index + 1, _numbered(value), null);
    }
    return (index, _numbered(value), _unended);
  }
  var end = at + 1;
  while (end < text.length && end - at <= 32 && _alnum(text.codeUnitAt(end))) {
    end++;
  }
  for (var stop = end; stop > at + 1; stop--) {
    final name = text.substring(at + 1, stop);
    if (stop < text.length &&
        text.codeUnitAt(stop) == _semicolon &&
        named.containsKey(name)) {
      return (stop + 1, named[name]!, null);
    }
    if (legacy.contains(name)) {
      if (attribute &&
          stop < text.length &&
          (text.codeUnitAt(stop) == _equals || _alnum(text.codeUnitAt(stop)))) {
        return null;
      }
      return (stop, named[name]!, _unended);
    }
  }
  return null;
}

/// [written], an attribute value as written, read as what it says.
String _decoded(String written) {
  if (!written.contains('&')) {
    return written;
  }
  final out = StringBuffer();
  var at = 0;
  while (at < written.length) {
    if (written.codeUnitAt(at) == _amp) {
      if (_reference(written, at, attribute: true) case (
        final end,
        final shows,
        _,
      )) {
        out.write(shows);
        at = end;
        continue;
      }
    }
    out.writeCharCode(written.codeUnitAt(at));
    at++;
  }
  return out.toString();
}

/// What a numbered reference to [value] stands for: the replacement
/// character for nought, a surrogate or anything past the last code point,
/// and windows-1252's character for a C1 control it has one for.
String _numbered(int value) {
  if (value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) {
    return '�';
  }
  return String.fromCharCode(_windows[value] ?? value);
}

const _unended = 'missing semicolon after character reference';

/// The elements whose content the standard reads as text up to their own
/// end tag.
const _raw = {
  'script', 'style', 'title', 'textarea', //
  'xmp', 'iframe', 'noembed', 'noframes', 'noscript',
};

/// The C1 controls a numbered reference reads as windows-1252 characters.
const _windows = {
  0x80: 0x20AC,
  0x82: 0x201A,
  0x83: 0x0192,
  0x84: 0x201E,
  0x85: 0x2026,
  0x86: 0x2020,
  0x87: 0x2021,
  0x88: 0x02C6,
  0x89: 0x2030,
  0x8A: 0x0160,
  0x8B: 0x2039,
  0x8C: 0x0152,
  0x8E: 0x017D,
  0x91: 0x2018,
  0x92: 0x2019,
  0x93: 0x201C,
  0x94: 0x201D,
  0x95: 0x2022,
  0x96: 0x2013,
  0x97: 0x2014,
  0x98: 0x02DC,
  0x99: 0x2122,
  0x9A: 0x0161,
  0x9B: 0x203A,
  0x9C: 0x0153,
  0x9E: 0x017E,
  0x9F: 0x0178,
};

/// [text] with its ASCII capitals made small, as the standard lower-cases
/// names.
String _lower(String text) {
  final units = text.codeUnits;
  if (!units.any((unit) => unit >= 0x41 && unit <= 0x5A)) {
    return text;
  }
  return String.fromCharCodes([
    for (final unit in units) unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit,
  ]);
}

int _digit(int unit, bool hex) {
  if (unit >= 0x30 && unit <= 0x39) {
    return unit - 0x30;
  }
  final small = unit | 0x20;
  return hex && small >= 0x61 && small <= 0x66 ? small - 0x57 : -1;
}

bool _letter(int unit) {
  final small = unit | 0x20;
  return small >= 0x61 && small <= 0x7A;
}

bool _alnum(int unit) => _letter(unit) || (unit >= 0x30 && unit <= 0x39);

bool _space(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0C ||
    unit == 0x0D;

/// Whether [unit] ends a tag's or an attribute's name.
bool _ends(int unit) => _space(unit) || unit == _slash || unit == _greater;

const _less = 0x3C;
const _greater = 0x3E;
const _slash = 0x2F;
const _bang = 0x21;
const _question = 0x3F;
const _underscore = 0x5F;
const _hyphen = 0x2D;
const _amp = 0x26;
const _hash = 0x23;
const _semicolon = 0x3B;
const _equals = 0x3D;
const _double = 0x22;
const _single = 0x27;
