import 'dart:math';

import 'package:libara/libara.dart';

import '../editing.dart';
import '../lexing.dart';
import '../limits.dart';
import '../positions.dart';

part 'declarations.dart';
part 'expressions.dart';
part 'patterns.dart';
part 'statements.dart';

/// Dart source, tokens as its scanner reads them, its brackets paired over
/// them, and its syntax: its declarations, statements, expressions and
/// patterns.
///
/// Layer 2 holds one token for each word, number, operator and mark, each
/// comment, `#comment`, and each run of whitespace, `#space`. A word is a
/// `#keyword` where Dart reserves or builds it in, and otherwise a `#name`;
/// a number is a `#number`; an operator or mark is named for itself. A
/// string is its quotes, each named for itself and the opening one with
/// its `r` where it is raw, its runs of characters, `#text`, its escape
/// sequences, each an `#escape` saying what it `shows`, and its
/// interpolations: a `$` and the name after it, or a `${`, the code within
/// and the `}` that closes it.
/// What does not scan is an `#error`.
///
/// A string or a comment may hold a line break, and an interpolation the
/// code of a string within a string, so where a token stands is not read
/// off the token alone or off the start of its line. Each token standing
/// within a string says so under `in`: the strings and interpolations open
/// where it starts, outermost first. A change is read again from the token
/// before it, with what that token says is open, to the first token past it
/// where the reading agrees with what the token says.
///
/// Layer 3 holds each pair of brackets, `parens`, `brackets` and `braces`,
/// and each `string` and `interpolation`, over the tokens from its opening
/// mark to its closing one. A mark that closes nothing, or that nothing
/// closes, is a diagnostic, and what nothing closes still reaches to the
/// mark that closes what holds it, or to the end.
///
/// Layer 3 holds the declarations too, at the top level and in the body of
/// each class, mixin, extension and enum, each named for its kind, `class`,
/// `mixin`, `enum`, `extension`, `typedef`, `function`, `method`,
/// `constructor`, `getter`, `setter`, `variable`, `field` or `directive`,
/// and each value of an enum, a `value`. A declaration runs from its first
/// token to its `;` or the braces of its body; one that is none of these
/// is a `declaration`. Each name a declaration declares is a `name` of its
/// own over the name's tokens, saying it under `name`, which is indexed,
/// so names are found without walking every token, and typing in one reads
/// again only that name.
///
/// The body of each function, method, constructor, getter and setter, of
/// each local function and of each closure is a `block` holding its
/// statements, each named for its kind: `if`, `for`, `while`, `do`,
/// `switch` with a `case` for each `case` or `default`, `try` with its
/// `catch` and `finally`, `return`, `break`, `continue`, `yield`,
/// `assert`, a `label`, a local `variable` or `function`, or, for an
/// expression, a `statement`.
///
/// Each expression of more than one token, wherever it stands, is named
/// for its kind, with Dart's precedence: `assignment`, `conditional`,
/// `binary`, `prefix` and `postfix`, each saying its `operator`; `is`,
/// `as` and `throw`; a `call`, of a function, a method or a constructor;
/// an `argument` named; an `index` or a `property`; a `cascade`, with a
/// `section` for each `..`; a `closure`; an `instantiation`, as `f<int>`;
/// a `list`, `set`, `map` or `record`, `const` where it is, with each
/// `entry`, `spread`, `aware` element, and `if` and `for`; a `switch`,
/// with a `case` for each arm; adjacent `strings`; and a `symbol`. A
/// type of more than one token is a `type`; each formal parameter, type
/// parameter, annotation and initializer of a constructor is a
/// `parameter`, `generic`, `annotation` or `initializer`.
///
/// Each pattern of more than one token, in a `case`, an arm of a switch
/// expression, an `if`-`case`, a declaration, a `for`-`in` or an
/// assignment, is a `pattern` saying its `form`: `constant`, `variable`,
/// `wildcard`, `list`, `map`, `record`, `object`, `relational`,
/// `logical`, `cast`, `check` for `?`, `assert` for `!`, or `rest` for
/// `...`. Each variable a pattern declares is a `name`; a guard after
/// `when` is read as an expression. What does not
/// read as it should is a diagnostic, such as `expected ;`; one says what
/// it does not expect by its kind where that is a name or a number, as
/// what is read again after a keystroke in one keeps what was said.
///
/// Only the characters of strings and comments are text, so a text edit
/// elsewhere is not valid, and no structural edit is carried out yet. A
/// document read in another syntax is not written as Dart.
final class Dart implements Format<Layered<int>, Sequence<int>> {
  /// The Dart syntax, reading within [limits].
  const Dart({this.limits = standard});

  /// What reading may build.
  final Limits limits;

  @override
  Result<Layered<int>> decode(Sequence<int> form) =>
      decoded('dart', _Grammar(limits), limits, form, indexed: const ['name']);

  /// [value]'s text, where it was read as Dart, and otherwise a refusal.
  @override
  Result<Sequence<int>> encode(Layered<int> value) => value.grammar is _Grammar
      ? Success(value.items)
      : const Failure(
          Kind.invalid,
          'dart: only a document read as Dart is written as Dart',
        );
}

final class _Grammar implements Grammar<int> {
  const _Grammar(this.limits);

  final Limits limits;

  @override
  int get depth => 3;

  @override
  Derived derive(Layered<int> document, int layer, Range region) => layer == 2
      ? tokens(
          document,
          region,
          limits,
          _Scanner(_open(document, region.start)).next,
        )
      : _derived(document, region);

  /// The pairs over [region] of layer 2's tokens, the marks that do not
  /// pair, and the declarations, where the tokens are at a level that
  /// declares: the top level, or the body of a class, mixin, extension or
  /// enum, which [region] may be whole. Where every token in [region] is
  /// of the kind the token in its place was, the ranges are those that
  /// were there, their names read again.
  Derived _derived(Layered<int> document, Range region) {
    if (_kept(document, region)) {
      return _again(document, region);
    }
    final pairing = _Pairing(document, region, limits);
    final (pairs, problems) = pairing.parse();
    if (problems.any((problem) => problem.get('limit') != null)) {
      return (ranges: pairs, diagnostics: problems);
    }
    final starts = {for (final pair in pairs) pair.start: pair};
    // Past the region, the tokens and pairs are as they stand, for what a
    // declaration ending at its end turns on.
    final beyond = _Tokens(document);
    ARange? token(int index) => index < region.start
        ? null
        : index < region.end
        ? pairing.tokens[index - region.start].$2
        : beyond(index);
    final slice = texts(document, pairing.tokens);
    final reader = _Declarations(
      token,
      (index) => index < region.end ? starts[index] : _opening(document, index),
      (token) =>
          pairing.tokens.isNotEmpty &&
              token.start >= pairing.tokens.first.$2.start &&
              token.end <= pairing.tokens.last.$2.end
          ? slice(token)
          : covered(document, token),
    );
    final level = _around(document, region);
    final held = _holder(document, level);
    final List<ARange> declared;
    if (_bodied(document, region) case final holder?) {
      declared = reader.read(
        region.start + 1,
        reader._inner(starts[region.start]!),
        members: true,
        enumerated: '${holder.get('')}' == 'enum',
      );
    } else if (_blocked(document, region)) {
      declared = [];
      reader.statements.block(starts[region.start]!, declared);
    } else if (level == null || held != null) {
      declared = reader.read(
        region.start,
        region.end,
        members: held != null,
        limit: level == null ? 1 << 62 : reader._inner(level),
      );
    } else if (_blocked(document, level)) {
      declared = [];
      reader.statements.statements(
        region.start,
        region.end,
        reader._inner(level),
        declared,
      );
    } else {
      declared = const [];
    }
    final most = limits.markers;
    if (most != null &&
        region.length + pairs.length + declared.length + problems.length >=
            most) {
      return (
        ranges: pairs,
        diagnostics: [
          ...problems,
          limited(span(region.start, 1), 'more than $most tokens and pairs'),
        ],
      );
    }
    return (
      ranges: [...pairs, ...declared],
      diagnostics: [...problems, ...reader.problems],
    );
  }

  /// The ranges and diagnostics over [region] as they were, each name
  /// read again from the tokens it now covers. They are taken from the
  /// previous version, where they stand as they were read: in this one, a
  /// range with an end among the tokens read again is cut back to them,
  /// and a token in this version is the one at its index in that.
  Derived _again(Layered<int> document, Range region) {
    String text(Range token) => covered(document, token);
    final previous = document.previous!;
    return (
      ranges: [
        for (final (_, range) in previous.within(3, region))
          if ('${range.get('')}' == 'name')
            ranged(range.start, range.length, {
              '': literal('name'),
              'name': literal(
                _joined([
                  for (final (_, token) in document.span(2, range)) token,
                ], text),
              ),
            })
          else
            range,
      ],
      diagnostics: [
        for (final problem in previous.diagnostics(3).items)
          if (problem.start >= region.start && problem.end <= region.end)
            problem as ARange,
      ],
    );
  }

  /// At layer 2, from the tokens before the change to the first token past
  /// it where the reading agrees with what was read before.
  ///
  /// At layer 3, where the change opens and closes nothing, only the
  /// changed tokens, unless they stand directly at a level that declares:
  /// then from the declaration before them to the first declaration past
  /// them that ends where one ended before. Otherwise the innermost pair
  /// around the changed tokens that, paired on its own, is still the pair
  /// it was, closed by its own mark and with no mark in it that closes
  /// nothing, which would close what holds it; and where that pair stands
  /// directly at a level that declares, the declaration it is part of.
  /// Every token where none is, or where a diagnostic touches it.
  @override
  Range affected(Layered<int> document, int layer, Range changed) =>
      layer == 2 ? _window(document, changed) : _pair(document, changed);

  @override
  Result<Derivation<int>> edit(Layered<int> document, Edit<int> change) =>
      refuse('dart', '${change.command} is not a Dart edit');

  /// What [change] makes of [document] where it changes only the
  /// characters of strings and comments.
  @override
  Result<Change<int>> valid(Layered<int> document, Edit<int> change) =>
      kept(document, change, text: _worded);

  /// [text] as the characters of a string, escaped where Dart would read a
  /// quote, an escape, an interpolation or a line break.
  @override
  List<int> escaped(List<int> text, {bool raw = false}) =>
      escaping(text, _escape, raw: raw);

  /// The characters of strings and comments are cut back by a move;
  /// nothing else is cut.
  @override
  Crossing crossing(Layered<int> document, int layer, ARange range) =>
      layer == 2 && _worded(range) ? Crossing.clamp : Crossing.refuse;

  Range _window(Layered<int> document, Range changed) {
    final length = document.items.length;
    // From the token before the one the change follows, which what the
    // change makes of that one may join, such as characters that a broken quote
    // no longer ends.
    var start = changed.start == 0
        ? 0
        : _holding(document, changed.start - 1)?.start ?? 0;
    if (start > 0) {
      start = _holding(document, start - 1)?.start ?? 0;
    }
    final open = _open(document, start);
    for (var size = changed.end - start + glimpse; ; size *= 2) {
      final end = min(start + size, length);
      final text = String.fromCharCodes(
        document.slice(span(start, end - start)).items,
      );
      final positions = Positions(text);
      final scanner = _Scanner([...open]);
      var unit = 0;
      while (unit < text.length) {
        final (next, name, _, _) = scanner.next(text, unit);
        unit = next;
        final position = start + positions[unit];
        // What a `$` is depends on what follows it, which a reading that
        // ends after it does not see.
        if (position > changed.end && position < end && name != r'$') {
          final token = _starting(document, position);
          if (token != null && _said(token) == scanner.frames.join(' ')) {
            return span(start, position - start);
          }
        }
      }
      if (end == length) {
        return span(start, length - start);
      }
    }
  }

  Range _pair(Layered<int> document, Range changed) {
    // Counting the tokens walks every one of them, so it waits until needed.
    Range whole() => span(0, document.layer(2).length);
    if (_kept(document, changed)) {
      return _named(document, changed);
    }
    // A diagnostic at an edge widens the region past it, so the level, or
    // the first block around it that none touches, is read whole instead:
    // a pair is read again only from its start.
    Range settled(Range region, ARange? level) {
      if (!_touched(document, region)) {
        return region;
      }
      for (var at = level; at != null;) {
        if (!_touched(document, at)) {
          return at;
        }
        final outer = _around(document, at);
        at = outer == null ? null : _block(document, outer);
      }
      return whole();
    }

    if (_unpaired(document, changed)) {
      final level = _around(document, changed);
      final held = _holder(document, level);
      if (level != null && held == null) {
        final block = _block(document, level);
        if (block == null) {
          return settled(_declaration(document, changed) ?? whole(), null);
        }
        return settled(_stretch(document, changed, block), block);
      }
      // An enum's values are read from the start of its body.
      if ('${held?.get('')}' == 'enum') {
        return level!;
      }
      return settled(_stretch(document, changed, level), level);
    }
    final around = [
      for (final (_, pair) in document.crossing(3, changed.start))
        if (changed.end < pair.end && _paired(pair)) pair,
    ]..sort((one, other) => one.length - other.length);
    for (final pair in around) {
      final (found, wrong) = _Pairing(document, pair, limits).parse();
      if (!found.any(
            (range) => range.start == pair.start && range.length == pair.length,
          ) ||
          wrong.any(
            (problem) =>
                '${problem.get('message')}'.endsWith(_stray) ||
                problem.start == pair.start,
          )) {
        continue;
      }
      Range region = pair;
      ARange? block;
      final outer = _around(document, pair);
      final held = _holder(document, outer);
      if ('${held?.get('')}' == 'enum') {
        region = outer!;
      } else if (outer != null && held == null) {
        // Within a body, a block reads alone, and any other pair with the
        // statements it stands in.
        block = _block(document, outer);
        if (block != null && !_blocked(document, pair)) {
          region = _stretch(document, pair, block);
        } else if (block == null && !_blocked(document, pair)) {
          region = _declaration(document, pair) ?? whole();
        }
      } else {
        ARange? declaration;
        for (final range in _containing(document, pair.start)) {
          if (_declared(range) &&
              range.start <= pair.start &&
              pair.end <= range.end &&
              (declaration == null || range.length < declaration.length)) {
            declaration = range;
          }
        }
        if (declaration == null) {
          return whole();
        }
        region = declaration;
      }
      return settled(region, block);
    }
    return whole();
  }

  /// From the declaration of [level] holding the token before [changed],
  /// or the start of the level, to the first declaration past [changed]
  /// that ends where one ended before, or the end of the level: declarations
  /// are read from where one starts, so from there on they read as before.
  Range _stretch(Layered<int> document, Range changed, ARange? level) {
    final tokens = _Tokens(document);
    final floor = level == null ? 0 : level.start + 1;
    // In a block, statements are read rather than declarations.
    final stating = level != null && _blocked(document, level);
    bool unit(ARange range) => stating
        ? !_paired(range) && '${range.get('')}' != 'name'
        : _declared(range);
    final declarations = _Declarations(
      tokens.call,
      (index) => _opening(document, index),
      (token) => covered(document, token),
    );
    final ceiling = level == null ? 1 << 62 : declarations._inner(level);
    // Within the level, which, where nothing closes it, what it holds may
    // end with.
    bool inside(ARange range) => range.start >= floor && range.end <= ceiling;
    ARange? declaration(int index) {
      ARange? outer;
      for (final range in _containing(document, index)) {
        if (unit(range) &&
            inside(range) &&
            (outer == null || range.length > outer.length)) {
          outer = range;
        }
      }
      return outer;
    }

    /// The start of the declaration holding the last token before [index]
    /// that is not whitespace or a comment, or of the level.
    int previous(int index) {
      var before = index - 1;
      while (before >= floor &&
          tokens(before) != null &&
          _quiet(tokens(before)!)) {
        before--;
      }
      return before < floor ? floor : declaration(before)?.start ?? floor;
    }

    // From the declaration before the one the change follows: where one
    // with no `;` ends turns on the token after it.
    final holding = previous(changed.start);
    final start = holding > floor ? previous(holding) : holding;
    final statements = declarations.statements;
    var at = start;
    while (true) {
      final next = stating
          ? statements.next(at, ceiling)
          : declarations.next(at, ceiling, members: level != null)?.end;
      if (next == null) {
        if (level != null) {
          return span(start, ceiling - start);
        }
        while (tokens(at) != null) {
          at++;
        }
        return span(start, at - start);
      }
      if (next > changed.end) {
        for (final range in _containing(document, next - 1)) {
          if (unit(range) && range.end == next && inside(range)) {
            return span(start, next - start);
          }
        }
      }
      at = next;
    }
  }
}

/// Whether the tokens over [region] of layer 2 are each of the kind the
/// token in its place was before the edit that made [document], which
/// libara keeps as its previous version while it derives this one: a name
/// still a name, a keyword the same word, a mark the same mark, string
/// characters and comments still those, each saying the same strings and
/// interpolations are open. Then no range of layer 3 changes but in what
/// its names say. The words a reading goes by, `type` and `_`, are taken
/// as changed.
bool _kept(Layered<int> document, Range region) {
  final previous = document.previous;
  final changes = document.changes;
  if (previous == null ||
      changes.length != 1 ||
      changes.single.layer != 1 ||
      region.length == 0) {
    return false;
  }
  final (at, removed, added) = switch (changes.single.command) {
    Insert(:final position, :final items) => (position, 0, items.length),
    Delete(:final span) => (span.start, span.length, 0),
    Replace(:final span, :final items) => (
      span.start,
      span.length,
      items.length,
    ),
    _ => (-1, 0, 0),
  };
  final now = document.span(2, region);
  final before = previous.span(2, region);
  if (at < 0 ||
      now.length != region.length ||
      before.length != region.length ||
      at < now.first.$2.start ||
      at + added > now.last.$2.end ||
      before.first.$2.start != now.first.$2.start ||
      before.last.$2.end != now.last.$2.end - added + removed) {
    return false;
  }
  for (var index = 0; index < now.length; index++) {
    final (one, other) = (now[index].$2, before[index].$2);
    final name = '${one.get('')}';
    if (name != '${other.get('')}' || _said(one) != _said(other)) {
      return false;
    }
    // A token clear of the edit is the one it was, text and all; so the
    // check gives the same answer over any stretch around the edit.
    if (one.end < at || one.start > at + added) {
      continue;
    }
    if (name == '#error') {
      return false;
    }
    if (name == '#keyword' &&
        covered(document, one) != covered(previous, other)) {
      return false;
    }
    if (name == '#name') {
      final (now, then) = (covered(document, one), covered(previous, other));
      // A member with no return type is a constructor where its name is
      // written as a type's is.
      if (const {'type', '_'}.contains(now) ||
          const {'type', '_'}.contains(then) ||
          _capital(now) != _capital(then)) {
        return false;
      }
    }
  }
  return true;
}

/// Whether [name] is written as a type's name is: its first letter, after
/// any underscores and dollars, a capital.
bool _capital(String name) {
  final letter = name.replaceFirst(RegExp(r'^[_$]+'), '');
  return letter.isNotEmpty &&
      letter[0] == letter[0].toUpperCase() &&
      letter[0] != letter[0].toLowerCase();
}

/// [changed], and every range of the previous version with an end among
/// the changed tokens, such as a name across them, which this version has
/// cut back to them: read again, each is as it was.
Range _named(Layered<int> document, Range changed) {
  final previous = document.previous!;
  var (start, end) = (changed.start, changed.end);
  for (final (_, range) in [
    ...previous.crossing(3, changed.start),
    ...previous.crossing(3, changed.end),
    ...previous.within(3, changed),
  ]) {
    if (range.start >= changed.start && range.start < changed.end ||
        range.end > changed.start && range.end <= changed.end) {
      start = min(start, range.start);
      end = max(end, range.end);
    }
  }
  return span(start, end - start);
}

/// The class, mixin, extension or enum whose body is [region] whole, if
/// any.
ARange? _bodied(Layered<int> document, Range region) {
  final opening = document.span(2, span(region.start, 1));
  if (opening.isEmpty || '${opening.single.$2.get('')}' != '{') {
    return null;
  }
  return _held(document, region);
}

/// Whether a diagnostic of layer 3 of [document] touches an edge of
/// [region] from outside it, which widens it to take the diagnostic in.
bool _touched(Layered<int> document, Range region) => document
    .diagnostics(3)
    .items
    .any(
      (problem) =>
          (problem.start < region.start || problem.end > region.end) &&
          (problem.start <= region.start && region.start <= problem.end ||
              problem.start <= region.end && region.end <= problem.end),
    );

/// The innermost declaration holding [region], which what stands within
/// it outside any block is read with, or null where none is.
ARange? _declaration(Layered<int> document, Range region) {
  ARange? declaration;
  for (final range in _containing(document, region.start)) {
    if (_declared(range) &&
        range.start <= region.start &&
        region.end <= range.end &&
        (declaration == null || range.length < declaration.length)) {
      declaration = range;
    }
  }
  return declaration;
}

/// Whether [range] is a block's braces: a range of layer 3 of [document]
/// over the same tokens is a `block`.
bool _blocked(Layered<int> document, Range range) =>
    range.length > 0 &&
    _containing(document, range.start).any(
      (other) =>
          other.start == range.start &&
          other.length == range.length &&
          '${other.get('')}' == 'block',
    );

/// The block that [pair] is the braces of, or else the innermost block
/// around it, or null where none is.
ARange? _block(Layered<int> document, ARange pair) {
  if (_blocked(document, pair)) {
    return pair;
  }
  ARange? inner;
  for (final (_, range) in document.crossing(3, pair.start)) {
    if (_paired(range) &&
        pair.end <= range.end &&
        (inner == null || range.length < inner.length) &&
        _blocked(document, range)) {
      inner = range;
    }
  }
  return inner;
}

/// Whether the [changed] tokens of [document] leave every pair as it was:
/// none of them opens or closes anything, none stands within a string
/// that a line break ends, no pair starts or ends among them, and no
/// diagnostic touches them.
bool _unpaired(Layered<int> document, Range changed) {
  final tokens = document.span(2, changed);
  final levels = {
    for (final (_, token) in tokens)
      _said(token).split(' ').where((frame) => frame != r'$').length,
  };
  if (levels.length > 1 ||
      tokens.any((token) {
        final name = '${token.$2.get('')}';
        return _marking.contains(name) || _quotes.contains(name);
      })) {
    return false;
  }
  final (start, end) = (changed.start, changed.end);
  // A pair that ends where the change starts, or starts where it ends, is
  // found a token either side. Past the last token, these find nothing.
  final from = max(0, start - 1);
  for (final (_, pair) in [
    ...document.crossing(3, from),
    ...document.crossing(3, start),
    ...document.crossing(3, end),
    ...document.crossing(3, end + 1),
    ...document.within(3, span(from, end + 1 - from)),
  ]) {
    if (_paired(pair) && start <= pair.start && pair.start <= end ||
        _paired(pair) && start <= pair.end && pair.end <= end) {
      return false;
    }
  }
  return !document
      .diagnostics(3)
      .items
      .any(
        (problem) =>
            _pairing(problem as ARange) &&
            problem.start <= end + 1 &&
            start <= problem.end + 1,
      );
}

/// Whether [problem] is one pairing finds, rather than one of a statement
/// that does not read as it should, which is read again with it.
bool _pairing(ARange problem) {
  final message = '${problem.get('message')}';
  return !message.startsWith('expected ') && !message.startsWith('unexpected ');
}

/// The marks other than quotes that open or close a pair.
const _marking = {'(', ')', '[', ']', '{', '}', r'${'};

/// The strings and interpolations open where the token starting at
/// [position] starts, as it says, or none at the start of the text.
List<String> _open(Layered<int> document, int position) {
  if (position == 0) {
    return [];
  }
  final token = _starting(document, position);
  final said = token == null ? '' : _said(token);
  return said.isEmpty ? [] : said.split(' ');
}

/// What [token] says is open where it starts.
String _said(ARange token) {
  final said = token.get('in');
  return said == null ? '' : '$said';
}

/// The token, not left over nothing by a change, that holds item
/// [position].
ARange? _holding(Layered<int> document, int position) {
  for (final (_, token) in document.crossing(2, position)) {
    return token;
  }
  return _starting(document, position);
}

/// The token, not left over nothing by a change, that starts at
/// [position].
ARange? _starting(Layered<int> document, int position) {
  for (final (_, token) in [
    ...document.within(
      2,
      span(position, min(1, document.items.length - position)),
    ),
    ...document.crossing(2, position + 1),
  ]) {
    if (token.start == position && token.length > 0) {
      return token;
    }
  }
  return null;
}

/// How the diagnostic for a mark closing nothing ends.
const _stray = ' closes nothing';

/// Whether [token] is characters: those of a string, or a comment.
bool _worded(ARange token) =>
    const {prose, '#escape', '#comment'}.contains('${token.get('')}');

/// Whether [code] ends a line.
bool _broken(int code) => code == 0x0A || code == 0x0D;

/// Whether [code] is whitespace between tokens.
bool _blank(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;

/// Whether [code] may start a name.
bool _initial(int code) =>
    code >= 0x61 && code <= 0x7A ||
    code >= 0x41 && code <= 0x5A ||
    code == 0x5F ||
    code == 0x24;

/// Whether [code] is a decimal digit.
bool _digit(int code) => code >= 0x30 && code <= 0x39;

/// Whether [code] may stand within a name.
bool _within(int code) => _initial(code) || _digit(code);

/// Whether [code] is a hexadecimal digit.
bool _hexadecimal(int code) =>
    _digit(code) ||
    code >= 0x61 && code <= 0x66 ||
    code >= 0x41 && code <= 0x46;

/// The words Dart reserves or builds in, which its scanner reads as
/// keywords wherever they stand.
const _keywords = {
  'abstract', 'as', 'assert', 'async', 'augment', 'await', 'base', 'break', //
  'case', 'catch', 'class', 'const', 'continue', 'covariant', 'default',
  'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
  'extension', 'external', 'factory', 'false', 'final', 'finally', 'for',
  'Function', 'get', 'hide', 'if', 'implements', 'import', 'in', 'inout',
  'interface', 'is', 'late', 'library', 'mixin', 'native', 'new', 'null',
  'of', 'on', 'operator', 'out', 'part', 'patch', 'required', 'rethrow',
  'return', 'sealed', 'set', 'show', 'source', 'static', 'super', 'switch',
  'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var', 'void', 'when',
  'while', 'with', 'yield',
};

/// The operators and marks, the longer of two that start alike first.
const _marks = [
  '>>>=', '...?', '>>>', '>>=', '<<=', '?..', '~/=', '??=', '&&=', '||=', //
  '[]=', '...', '==', '!=', '<=', '>=', '&&', '||', '++', '--', '+=', '-=',
  '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '??', '?.', '..', '=>',
  '~/', '[]', '+', '-', '*', '/', '%', '=', '<', '>', '!', '~', '^', '&',
  '|', '?', ':', ';', ',', '.', '(', ')', '[', ']', '{', '}', '@', '#', '`',
];

/// The quotes a string opens with.
const _quotes = {"'", '"', "'''", '"""', "r'", 'r"', "r'''", 'r"""'};

/// What each single-letter escape shows.
const _escapes = {
  0x6E: '\n',
  0x72: '\r',
  0x66: '\f',
  0x62: '\b',
  0x74: '\t',
  0x76: '\v',
};

/// [text] as the characters of a string.
String _escape(String text) {
  final written = StringBuffer();
  for (final code in text.codeUnits) {
    written.write(switch (code) {
      0x27 => r"\'",
      0x22 => r'\"',
      0x5C => r'\\',
      0x24 => r'\$',
      0x0A => r'\n',
      0x0D => r'\r',
      < 0x20 => '\\x${code.toRadixString(16).padLeft(2, '0')}',
      _ => String.fromCharCode(code),
    });
  }
  return written.toString();
}

/// Reads Dart's tokens one after another, knowing what is open: each
/// string by the quote it opened with, each interpolation as `{` and how
/// many braces stand open in its code, and `$` where a name interpolates.
final class _Scanner {
  _Scanner(this.frames);

  final List<String> frames;

  /// The token starting at [at] in [text], saying what is open where it
  /// starts.
  Token next(String text, int at) {
    final open = frames.isEmpty ? null : literal(frames.join(' '));
    final (end, name, attributes, problem) = _read(text, at);
    return (
      end,
      name,
      open == null ? attributes : {...attributes, 'in': open},
      problem,
    );
  }

  Token _read(String text, int at) {
    final frame = frames.isEmpty ? null : frames.last;
    if (frame == r'$') {
      frames.removeLast();
      return _word(text, at, interpolated: true);
    }
    if (frame != null && !frame.startsWith('{')) {
      return _string(text, at, frame);
    }
    return _code(text, at);
  }

  Token _code(String text, int at) {
    final code = text.codeUnitAt(at);
    if (_blank(code)) {
      var end = at + 1;
      while (end < text.length && _blank(text.codeUnitAt(end))) {
        end++;
      }
      return (end, '#space', const {}, null);
    }
    if (at == 0 && text.startsWith('#!')) {
      return (_line(text, at), '#comment', const {}, null);
    }
    if (text.startsWith('//', at)) {
      return (_line(text, at), '#comment', const {}, null);
    }
    if (text.startsWith('/*', at)) {
      return _comment(text, at);
    }
    for (final quote in ["r'''", 'r"""', "'''", '"""', "r'", 'r"', "'", '"']) {
      if (text.startsWith(quote, at)) {
        frames.add(quote);
        return (at + quote.length, quote, const {}, null);
      }
    }
    if (_initial(code)) {
      return _word(text, at);
    }
    if (_digit(code) ||
        code == 0x2E &&
            at + 1 < text.length &&
            _digit(text.codeUnitAt(at + 1))) {
      return _number(text, at);
    }
    if (code == 0x7B || code == 0x7D) {
      final frame = frames.isEmpty ? null : frames.last;
      if (frame != null) {
        final braces = int.parse(frame.substring(1));
        frames.removeLast();
        if (code == 0x7B) {
          frames.add('{${braces + 1}');
        } else if (braces > 0) {
          frames.add('{${braces - 1}');
        }
      }
      return (at + 1, String.fromCharCode(code), const {}, null);
    }
    for (final mark in _marks) {
      if (text.startsWith(mark, at)) {
        return (at + mark.length, mark, const {}, null);
      }
    }
    final width = code >= 0xD800 && code < 0xDC00 && at + 1 < text.length
        ? 2
        : 1;
    return (at + width, '#error', const {}, 'not a Dart character');
  }

  /// The name or keyword at [at], which holds no `$` where it
  /// [interpolated].
  Token _word(String text, int at, {bool interpolated = false}) {
    var end = at;
    while (end < text.length &&
        _within(text.codeUnitAt(end)) &&
        !(interpolated && text.codeUnitAt(end) == 0x24)) {
      end++;
    }
    if (end == at) {
      return (at + 1, '#error', const {}, 'not a name');
    }
    final word = text.substring(at, end);
    return (
      end,
      _keywords.contains(word) ? '#keyword' : '#name',
      const {},
      null,
    );
  }

  /// The number at [at]: decimal or hexadecimal, its digits perhaps apart
  /// by underscores.
  Token _number(String text, int at) {
    int digits(int from, bool Function(int) test) {
      var end = from;
      while (end < text.length) {
        final code = text.codeUnitAt(end);
        if (test(code)) {
          end++;
        } else if (code == 0x5F &&
            end > from &&
            end + 1 < text.length &&
            (test(text.codeUnitAt(end + 1)) ||
                text.codeUnitAt(end + 1) == 0x5F)) {
          end++;
        } else {
          break;
        }
      }
      return end;
    }

    if (text.startsWith('0x', at) || text.startsWith('0X', at)) {
      final end = digits(at + 2, _hexadecimal);
      return end == at + 2
          ? (end, '#error', const {}, 'a hexadecimal number with no digits')
          : (end, '#number', const {}, null);
    }
    var end = digits(at, _digit);
    if (end + 1 < text.length &&
        text.codeUnitAt(end) == 0x2E &&
        _digit(text.codeUnitAt(end + 1))) {
      end = digits(end + 1, _digit);
    }
    if (end < text.length && (text.codeUnitAt(end) | 0x20) == 0x65) {
      var from = end + 1;
      if (from < text.length &&
          (text.codeUnitAt(from) == 0x2B || text.codeUnitAt(from) == 0x2D)) {
        from++;
      }
      if (from < text.length && _digit(text.codeUnitAt(from))) {
        end = digits(from, _digit);
      }
    }
    return (end, '#number', const {}, null);
  }

  /// The comment opening with `/*` at [at], which holds comments of its
  /// own.
  static Token _comment(String text, int at) {
    var depth = 0;
    var end = at;
    while (end < text.length) {
      if (text.startsWith('/*', end)) {
        depth++;
        end += 2;
      } else if (text.startsWith('*/', end)) {
        depth--;
        end += 2;
        if (depth == 0) {
          return (end, '#comment', const {}, null);
        }
      } else {
        end++;
      }
    }
    return (end, '#comment', const {}, 'unclosed comment');
  }

  /// Where the line that [at] stands on ends, before its line break.
  static int _line(String text, int at) {
    var end = at;
    while (end < text.length && !_broken(text.codeUnitAt(end))) {
      end++;
    }
    return end;
  }

  /// The token at [at] within the string that opened with [frame].
  Token _string(String text, int at, String frame) {
    final raw = frame.startsWith('r');
    final quote = raw ? frame.substring(1) : frame;
    final single = quote.length == 1;
    final code = text.codeUnitAt(at);
    if (text.startsWith(quote, at)) {
      frames.removeLast();
      return (at + quote.length, quote, const {}, null);
    }
    if (single && _broken(code)) {
      // A line break ends a string that opened with one quote; what holds
      // it says that nothing closed it.
      frames.removeLast();
      return _code(text, at);
    }
    if (!raw && code == 0x5C) {
      return _escaped(text, at, single);
    }
    if (!raw && code == 0x24) {
      if (text.startsWith(r'${', at)) {
        frames.add('{0');
        return (at + 2, r'${', const {}, null);
      }
      if (at + 1 < text.length &&
          _initial(text.codeUnitAt(at + 1)) &&
          text.codeUnitAt(at + 1) != 0x24) {
        frames.add(r'$');
        return (at + 1, r'$', const {}, null);
      }
      return (at + 1, '#error', const {}, r'a $ that interpolates nothing');
    }
    // Characters of many lines are a token a line, so a keystroke among them
    // reads one line again rather than all of them.
    var end = at;
    while (end < text.length) {
      final next = text.codeUnitAt(end);
      if (end > at &&
          (!raw && (next == 0x5C || next == 0x24) ||
              single && _broken(next) ||
              text.startsWith(quote, end))) {
        break;
      }
      end++;
      if (_broken(next)) {
        if (next == 0x0D && end < text.length && text.codeUnitAt(end) == 0x0A) {
          end++;
        }
        break;
      }
    }
    return (end, prose, const {}, null);
  }

  /// The escape starting with the backslash at [at], in a string of one
  /// line where [single].
  static Token _escaped(String text, int at, bool single) {
    if (at + 1 >= text.length || single && _broken(text.codeUnitAt(at + 1))) {
      return (at + 1, '#error', const {}, 'not an escape');
    }
    final letter = text.codeUnitAt(at + 1);
    if (_escapes[letter] case final shows?) {
      return (at + 2, '#escape', {'shows': literal(shows)}, null);
    }
    if (letter == 0x78) {
      return _coded(text, at, at + 2, at + 4);
    }
    if (letter == 0x75) {
      if (text.startsWith('{', at + 2)) {
        // Its digits, up to six, and then its brace: what it is depends on
        // nothing past where it ends but the one character after.
        var close = at + 3;
        while (close < text.length &&
            close < at + 9 &&
            _hexadecimal(text.codeUnitAt(close))) {
          close++;
        }
        return close == at + 3 ||
                close >= text.length ||
                text.codeUnitAt(close) != 0x7D
            ? (close, '#error', const {}, 'not an escape')
            : _coded(text, at, at + 3, close, past: 1);
      }
      return _coded(text, at, at + 2, at + 6);
    }
    final width = letter >= 0xD800 && letter < 0xDC00 && at + 2 < text.length
        ? 3
        : 2;
    return (
      at + width,
      '#escape',
      {'shows': literal(text.substring(at + 1, at + width))},
      null,
    );
  }

  /// The escape at [at] whose hexadecimal digits run from [from] to [to],
  /// and [past] marks more after them.
  static Token _coded(String text, int at, int from, int to, {int past = 0}) {
    if (to > text.length ||
        from == to ||
        !text.substring(from, to).codeUnits.every(_hexadecimal)) {
      return (from, '#error', const {}, 'not an escape');
    }
    final value = int.parse(text.substring(from, to), radix: 16);
    if (value > 0x10FFFF) {
      return (to + past, '#error', const {}, 'not a character');
    }
    return (
      to + past,
      '#escape',
      {'shows': literal(String.fromCharCode(value))},
      null,
    );
  }
}

/// What is open while the tokens are paired: a bracket, a string or an
/// interpolation, from token [start].
typedef _Open = ({String kind, int start});

/// The pairs over a region of layer 2's tokens.
final class _Pairing {
  _Pairing(this.document, this.region, this.limits)
    : tokens = document.span(2, region);

  final Layered<int> document;
  final Range region;
  final Limits limits;
  final List<(Marker, ARange)> tokens;

  final pairs = <ARange>[];
  final problems = <ARange>[];
  final stack = <_Open>[];

  Derived run() {
    final (found, wrong) = parse();
    return (ranges: found, diagnostics: wrong);
  }

  /// The pairs the region's tokens make, and the marks that do not pair,
  /// read from what the first token says is open. The pairing stops at a
  /// pair nested deeper than the limit, or where the tokens, pairs and
  /// diagnostics would be more marked ranges than it allows.
  (List<ARange>, List<ARange>) parse() {
    final most = limits.markers;
    final deepest = limits.depth;
    final base = tokens.isEmpty ? 0 : _levels(tokens.first.$2);
    for (var at = 0; at < tokens.length; at++) {
      final token = tokens[at].$2;
      final name = '${token.get('')}';
      final index = region.start + at;
      // A string that opened with one quote ends at a line break with
      // nothing to close it, before whatever token follows the break.
      final levels = _levels(token) - base;
      while (_nested() > levels) {
        _end(index, 'string', closed: false);
      }
      if (name == '#space' || name == '#comment') {
        continue;
      }
      if (most != null &&
          region.length + pairs.length + problems.length >= most) {
        problems.add(
          limited(span(index, 1), 'more than $most tokens and pairs'),
        );
        return (pairs, problems);
      }
      final opening = switch (name) {
        '(' => 'parens',
        '[' => 'brackets',
        '{' => 'braces',
        r'${' => 'interpolation',
        _ when _quotes.contains(name) && !_quoted(token) => 'string',
        _ => null,
      };
      if (opening != null) {
        if (deepest != null && stack.length >= deepest) {
          problems.add(
            limited(span(index, 1), 'pairs nested deeper than $deepest'),
          );
          return (pairs, problems);
        }
        stack.add((kind: opening, start: index));
        continue;
      }
      final closing = switch (name) {
        ')' => 'parens',
        ']' => 'brackets',
        '}' when _said(token).endsWith('{0') => 'interpolation',
        '}' => 'braces',
        _ when _quotes.contains(name) => 'string',
        _ => null,
      };
      if (closing != null) {
        _end(index, closing);
      }
    }
    while (stack.isNotEmpty) {
      _unclosed(region.end);
    }
    return (pairs, problems);
  }

  /// How many strings and interpolations [token] says are open.
  static int _levels(ARange token) {
    final said = _said(token);
    if (said.isEmpty) {
      return 0;
    }
    return said.split(' ').where((frame) => frame != r'$').length;
  }

  /// Whether [token], a quote, stands within the string it closes.
  static bool _quoted(ARange token) {
    final said = _said(token);
    return said.isNotEmpty && !said.split(' ').last.startsWith('{');
  }

  /// How many strings and interpolations stand open.
  int _nested() => stack
      .where((open) => open.kind == 'string' || open.kind == 'interpolation')
      .length;

  /// Closes the innermost [kind] open within the innermost string or
  /// interpolation with the token at [index], or, where nothing closes it,
  /// at that token, and whatever is open within it.
  void _end(int index, String kind, {bool closed = true}) {
    final nesting = kind == 'string' || kind == 'interpolation';
    var which = stack.length - 1;
    while (which >= 0 && stack[which].kind != kind) {
      if (!nesting &&
          (stack[which].kind == 'string' ||
              stack[which].kind == 'interpolation')) {
        which = -1;
        break;
      }
      which--;
    }
    if (which < 0) {
      problems.add(
        ARange.from(span(index, 1), {
          'message': literal(
            '${'${tokens[index - region.start].$2.get('')}'}$_stray',
          ),
        }),
      );
      return;
    }
    while (stack.length > which + 1) {
      _unclosed(index);
    }
    if (!closed) {
      _unclosed(index);
      return;
    }
    final open = stack.removeLast();
    pairs.add(ranged(open.start, index + 1 - open.start, {'': literal(kind)}));
  }

  /// Closes what is open innermost, which nothing closes, at token [end].
  void _unclosed(int end) {
    final open = stack.removeLast();
    problems.add(
      ARange.from(span(open.start, 1), {
        'message': literal('unclosed ${open.kind}'),
      }),
    );
    pairs.add(ranged(open.start, end - open.start, {'': literal(open.kind)}));
  }
}
