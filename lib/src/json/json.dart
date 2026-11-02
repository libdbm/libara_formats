import 'dart:math';

import 'package:libara/libara.dart';

import '../editing.dart';
import '../formats.dart';
import '../lexing.dart';
import '../limits.dart';

/// JSON, as RFC 8259 reads it, kept as written rather than as the values
/// it holds.
///
/// Layer 2 holds one token for each of the six punctuation marks, under the
/// mark itself, and one for each run of whitespace, `#space`. A string,
/// from its quote to its quote, is a `#string` saying the characters it
/// holds, its escape sequences decoded, as `shows`; one that no quote
/// closes ends at the line break, which no string holds. A number is a
/// `#number` and `true`, `false` and `null` a `#literal`, each saying what
/// it shows. What does not scan is an `#error` token with a diagnostic over
/// it, and a string holding an escape sequence that says nothing or a
/// character no string may hold has one too. Every token is read from its own start without looking
/// back, as an XML tag is.
///
/// Layer 3 holds the values over those tokens: each `object` and `array`
/// from its opening mark to its closing one, each `string`, `number`,
/// `boolean` and `null`, and each `member` of an object, from its name to
/// its value, with its name decoded under `key`. What does not parse is a
/// diagnostic, and the values around it are read as well as they can be:
/// an array or object that nothing closes reaches to the mark that closes
/// what holds it, or to the end, so every value lies within the one that
/// holds it.
///
/// Only strings are text: an edit to a document is either a
/// text edit within a string or not an edit JSON makes, so no structural
/// edit is carried out yet. A document read in another syntax is not
/// written as JSON, since no element of it says what value it is.
final class JSON implements Syntax {
  /// The JSON syntax, reading within [limits].
  const JSON({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      decoded('json', _Grammar(limits), limits, form);

  /// [value]'s text, where it was read as JSON, and otherwise a refusal.
  @override
  Result<Sequence<int>> encode(Layered<int> value) => value.grammar is _Grammar
      ? Success(value.items)
      : const Failure(
          Kind.invalid,
          'json: only a document read as JSON is written as JSON',
        );
}

final class _Grammar implements Grammar<int> {
  const _Grammar(this.limits);

  final Limits limits;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) => layer == 2
      ? tokens(document, region, limits, _next)
      : _Parser(document, region, limits).run(_context(document, region));

  /// At layer 2, from the token before the change to the first unchanged
  /// token past it. At layer 3, the
  /// innermost array or object strictly around the changed tokens that,
  /// read on its own, is still the value it was, closed by its own mark and
  /// with no mark in it that closes nothing, and is held by another, with
  /// the member it is the value of: what lies outside it reads as it did,
  /// since a mark that closes nothing within it would close what holds it.
  /// Every token where none is, or where a diagnostic touches it.
  @override
  Range affected(Layered<int> document, int layer, Range changed) => layer == 2
      ? relexed(document, changed, _next)
      : _value(document, changed);

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      refuse('json', '${change.command} is not a JSON edit');

  /// What [change] makes of [document] where it changes only the
  /// characters of strings, within their quotes.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      kept(document, change, text: _stringed);

  /// [text] as the characters of a string, escaped where JSON would read a
  /// quote, an escape or a character no string holds.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) =>
      escaping(text, _escape, raw: raw);

  /// Nothing is cut by a move: half a string is not one.
  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      Crossing.refuse;

  Range _value(Layered<int> document, Range changed) {
    // Counting the tokens walks every one of them, so it waits until needed.
    Range whole() => span(0, document.layer(2).length);
    final around = [
      for (final (_, value) in document.crossing(3, changed.start))
        if (changed.end < value.end && _nested(value)) value,
    ]..sort((one, other) => one.length - other.length);
    // The largest holds no other here, so it is read with the whole.
    for (final value in around.take(max(0, around.length - 1))) {
      final (found, wrong) = _Parser(document, value, limits).parse(null);
      if (!found.any(
            (range) =>
                range.start == value.start && range.length == value.length,
          ) ||
          wrong.any(
            (problem) =>
                '${problem.get('message')}'.endsWith(_stray) ||
                problem.start == value.start,
          )) {
        continue;
      }
      final member = [
        for (final (_, range) in document.crossing(3, value.start))
          if (range.end == value.end && range.get('') == _member) range,
      ];
      final region = member.isEmpty ? value : member.single;
      final touched = document
          .diagnostics(3)
          .items
          .any(
            (problem) =>
                problem.start <= region.start && region.start <= problem.end ||
                problem.start <= region.end && region.end <= problem.end,
          );
      return touched ? whole() : region;
    }
    return whole();
  }

  /// The innermost array or object around [region], which a region less
  /// than the whole is read within.
  static ARange? _context(Layered<int> document, Range region) {
    ARange? inner;
    for (final (_, value) in document.crossing(3, region.start)) {
      if (region.end <= value.end &&
          _nested(value) &&
          (inner == null || value.length < inner.length)) {
        inner = value;
      }
    }
    return inner;
  }
}

/// How the diagnostic for a mark closing nothing ends.
const _stray = ' closes nothing';

/// The name of a member of an object.
final _member = literal('member');

/// Whether [value] is an array or an object.
bool _nested(ARange value) {
  final name = value.get('');
  return name == literal('object') || name == literal('array');
}

/// Whether [token] is a string, whose characters are text.
bool _stringed(ARange token) => token.get('') == literal('#string');

/// Whether [code] ends a line.
bool _broken(int code) => code == 0x0A || code == 0x0D;

/// Whether [code] is whitespace between tokens.
bool _blank(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;

/// Whether [code] ends a run of what is not a token of its own.
bool _bounding(int code) => _blank(code) || '{}[]:,"'.codeUnits.contains(code);

/// What a JSON number looks like, whole.
final _numeral = RegExp(r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$');

/// The four digits of a `\u` escape.
final _hexadecimal = RegExp(r'^[0-9a-fA-F]{4}$');

/// What each single-letter escape shows.
const _escapes = {
  0x22: '"',
  0x5C: r'\',
  0x2F: '/',
  0x62: '\b',
  0x66: '\f',
  0x6E: '\n',
  0x72: '\r',
  0x74: '\t',
};

/// [text] as the characters of a string.
String _escape(String text) {
  final written = StringBuffer();
  for (final code in text.codeUnits) {
    written.write(switch (code) {
      0x22 => r'\"',
      0x5C => r'\\',
      0x0A => r'\n',
      0x0D => r'\r',
      0x09 => r'\t',
      < 0x20 => '\\u${code.toRadixString(16).padLeft(4, '0')}',
      _ => String.fromCharCode(code),
    });
  }
  return written.toString();
}

/// The token starting at [at] in [text].
Token _next(String text, int at) {
  final code = text.codeUnitAt(at);
  if (_blank(code)) {
    var end = at + 1;
    while (end < text.length && _blank(text.codeUnitAt(end))) {
      end++;
    }
    return (end, '#space', const {}, null);
  }
  if (code == 0x22) {
    return _string(text, at);
  }
  if (_bounding(code)) {
    return (at + 1, String.fromCharCode(code), const {}, null);
  }
  var end = at + 1;
  while (end < text.length && !_bounding(text.codeUnitAt(end))) {
    end++;
  }
  final word = text.substring(at, end);
  final shows = {'shows': literal(word)};
  if (word == 'true' || word == 'false' || word == 'null') {
    return (end, '#literal', shows, null);
  }
  if (_numeral.hasMatch(word)) {
    return (end, '#number', shows, null);
  }
  return (end, '#error', const {}, '"$word" is not a JSON value');
}

/// The string whose quote is at [at]: to its closing quote, or to the line
/// break or end where none closes it, saying the characters it shows
/// and the first thing wrong with it.
Token _string(String text, int at) {
  final characters = StringBuffer();
  String? problem;
  var end = at + 1;
  while (true) {
    if (end >= text.length || _broken(text.codeUnitAt(end))) {
      problem = 'unclosed "';
      break;
    }
    final code = text.codeUnitAt(end);
    if (code == 0x22) {
      end++;
      break;
    }
    if (code == 0x5C) {
      final (past, shows) = _escaped(text, end);
      if (shows == null) {
        problem ??= 'not an escape';
        characters.write(text.substring(end, past));
      } else {
        characters.write(shows);
      }
      end = past;
      continue;
    }
    if (code < 0x20) {
      problem ??= 'a control character in a string';
    }
    characters.writeCharCode(code);
    end++;
  }
  return (end, '#string', {'shows': literal(characters.toString())}, problem);
}

/// Where the escape starting with the backslash at [at] ends, and what it
/// shows, or null where it is not one. A line break after the backslash
/// is left to end the string, as it would anywhere in one.
(int, String?) _escaped(String text, int at) {
  final letter = at + 1 < text.length ? text.codeUnitAt(at + 1) : -1;
  if (letter < 0 || _broken(letter)) {
    return (at + 1, null);
  }
  if (_escapes[letter] case final shows?) {
    return (at + 2, shows);
  }
  final unit = _hex(text, at);
  if (unit < 0) {
    return (at + 2, null);
  }
  // A pair of escapes for one character outside the first plane is one
  // character, since neither half of it is a character.
  final low = _hex(text, at + 6);
  return unit >= 0xD800 && unit < 0xDC00 && low >= 0xDC00 && low < 0xE000
      ? (at + 12, String.fromCharCodes([unit, low]))
      : (at + 6, String.fromCharCode(unit));
}

/// The code unit the `\u` escape at [at] says, or -1.
int _hex(String text, int at) {
  if (at + 6 > text.length || !text.startsWith(r'\u', at)) {
    return -1;
  }
  final digits = text.substring(at + 2, at + 6);
  return _hexadecimal.hasMatch(digits) ? int.parse(digits, radix: 16) : -1;
}

/// What is open while the tokens are read: an array, an object, a member
/// of one, or the text itself, from token [start], and how far into it the
/// reading is.
final class _Frame {
  _Frame(this.kind, this.start);

  final String kind;
  final int start;

  /// In an array or object: 0 after it opens, 1 after a value or member,
  /// 2 after a comma. In a member: 0 after its name, 1 after its colon, 2
  /// once its value has opened. In the text: 0 before its value, 1 after.
  int state = 0;

  /// A member's name.
  String key = '';
}

/// Reads the values over a region of layer 2's tokens.
final class _Parser {
  _Parser(this.document, this.region, this.limits)
    : tokens = document.span(2, region);

  final Layered<int> document;
  final Range region;
  final Limits limits;
  final List<(Marker, ARange)> tokens;

  final values = <ARange>[];
  final problems = <ARange>[];
  final stack = <_Frame>[];

  /// What the region reads as, within [context], or as the whole text.
  Derived run(ARange? context) {
    final (found, wrong) = parse(context);
    return (ranges: found, diagnostics: wrong);
  }

  /// The values the region's tokens read as, and what does not parse,
  /// within the array or object [context], or as a text of its own. The
  /// reading stops at a value nested deeper than the limit, or where the
  /// tokens, values and diagnostics would be more marked ranges than it
  /// allows.
  (List<ARange>, List<ARange>) parse(ARange? context) {
    stack.add(
      _Frame(context == null ? 'text' : '${context.get('')}', -1)
        ..state = context == null ? 0 : 2,
    );
    final most = limits.markers;
    var at = 0;
    while (at < tokens.length) {
      final token = tokens[at].$2;
      final name = '${token.get('')}';
      if (name == '#space' || name == '#error') {
        at++;
        continue;
      }
      if (most != null &&
          region.length + values.length + problems.length >= most) {
        problems.add(limited(_at(at), 'more than $most tokens and values'));
        return (values, problems);
      }
      final next = _step(at, name);
      if (next < 0) {
        return (values, problems);
      }
      at = next;
    }
    while (stack.length > 1) {
      if (stack.last.kind == 'member') {
        stack.removeLast();
      } else {
        _unclosed(region.end);
      }
    }
    return (values, problems);
  }

  /// Reads the token at [at], called [name], and returns where to read
  /// next, or -1 where a limit stops the reading.
  int _step(int at, String name) {
    final frame = stack.last;
    if (name == '}' || name == ']') {
      return _close(at, name == '}' ? 'object' : 'array');
    }
    switch (frame.kind) {
      case 'object':
        if (frame.state == 1) {
          if (name == ',') {
            frame.state = 2;
            return at + 1;
          }
          _problem(at, 'expected , or }');
          if (name != '#string') {
            return at + 1;
          }
        }
        if (name != '#string') {
          _problem(at, 'expected a member name');
          return at + 1;
        }
        values.add(_ranged(at, at + 1, 'string'));
        frame.state = 1;
        stack.add(
          _Frame('member', region.start + at)
            ..key = '${tokens[at].$2.get('shows')}',
        );
        return at + 1;
      case 'member':
        if (frame.state == 0) {
          if (name == ':') {
            frame.state = 1;
            return at + 1;
          }
          _problem(at, 'expected :');
          if (name == ',') {
            stack.removeLast();
            stack.last.state = 1;
            return at;
          }
          frame.state = 1;
        }
        if (name == ',' || name == ':') {
          _problem(at, 'expected a value');
          stack.removeLast();
          stack.last.state = 1;
          return at;
        }
        return _value(at, name);
      default:
        if (name == ',' && frame.kind == 'array' && frame.state == 1) {
          frame.state = 2;
          return at + 1;
        }
        if (name == ',' || name == ':') {
          _problem(at, 'expected a value');
          return at + 1;
        }
        if (frame.state == 1) {
          _problem(
            at,
            frame.kind == 'array' ? 'expected , or ]' : 'more than one value',
          );
        }
        return _value(at, name);
    }
  }

  /// Reads the value starting with the token at [at], called [name].
  int _value(int at, String name) {
    final index = region.start + at;
    if (name == '{' || name == '[') {
      final deepest = limits.depth;
      if (deepest != null &&
          stack.where((frame) => frame.start >= 0).length >= deepest) {
        problems.add(limited(_at(at), 'values nested deeper than $deepest'));
        return -1;
      }
      stack.last.state = 2;
      stack.add(_Frame(name == '{' ? 'object' : 'array', index));
      return at + 1;
    }
    final called = switch (name) {
      '#string' => 'string',
      '#number' => 'number',
      '#literal' =>
        tokens[at].$2.get('shows') == literal('null') ? 'null' : 'boolean',
      _ => null,
    };
    if (called == null) {
      _problem(at, 'expected a value');
      return at + 1;
    }
    _done(index, index + 1, called);
    return at + 1;
  }

  /// Closes the innermost array or object of [kind] with the token at
  /// [at], and whatever is open within it, or reports that it closes
  /// nothing.
  int _close(int at, String kind) {
    final index = region.start + at;
    final which = stack.lastIndexWhere(
      (frame) => frame.kind == kind && frame.start >= 0,
    );
    if (which < 0) {
      _problem(at, '${kind == 'object' ? '}' : ']'}$_stray');
      return at + 1;
    }
    while (stack.length > which + 1) {
      final open = stack.last;
      if (open.kind != 'member') {
        _unclosed(index);
      } else {
        stack.removeLast();
        _problem(at, open.state == 0 ? 'expected :' : 'expected a value');
      }
    }
    final frame = stack.removeLast();
    if (frame.state == 2) {
      _problem(at, 'a comma before the end');
    }
    _done(frame.start, index + 1, kind);
    return at + 1;
  }

  /// Closes the array or object open innermost, which no mark closes, at
  /// token [end].
  void _unclosed(int end) {
    final open = stack.removeLast();
    _problem(open.start - region.start, 'unclosed ${open.kind}');
    _done(open.start, end, open.kind);
  }

  /// Records the value of [name] from token [start] to [end], and closes
  /// the member it is the value of.
  void _done(int start, int end, String name) {
    values.add(ranged(start, end - start, {'': literal(name)}));
    final frame = stack.last;
    if (frame.kind == 'member') {
      stack.removeLast();
      values.add(
        ranged(frame.start, end - frame.start, {
          '': _member,
          'key': literal(frame.key),
        }),
      );
    }
    stack.last.state = 1;
  }

  /// The value of [name] over the region's tokens from [at] to [end].
  ARange _ranged(int at, int end, String name) =>
      ranged(region.start + at, end - at, {'': literal(name)});

  /// The region's token at [at], as a range of layer 2.
  Range _at(int at) => span(region.start + at, 1);

  void _problem(int at, String message) {
    problems.add(ARange.from(_at(at), {'message': literal(message)}));
  }
}
