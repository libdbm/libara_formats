part of 'dart.dart';

/// The words that start no statement, though a statement may hold them.
const _unstarting = {'else', 'case', 'default', 'catch', 'finally'};

/// The words that may stand before a local variable's type or name.
const _declaring = {'late', 'final', 'const', 'var'};

/// Reads the statements of bodies: each block, statement, and what each
/// holds, its expressions read by [_Expressions].
///
/// What reads a statement adds its ranges to a list where one is given;
/// where none is, it only finds where the statement ends, looking no
/// further into the pairs it holds.
final class _Statements {
  _Statements(this.reader);

  final _Declarations reader;

  /// Reads the expressions the statements hold.
  late final expressions = _Expressions(this);

  /// What the statements being read say is wrong with them, innermost
  /// last.
  final _pending = <String>[];

  /// The block over [braces], added to [found], and what it holds.
  void block(ARange braces, List<ARange> found) {
    found.add(ranged(braces.start, braces.length, {'': literal('block')}));
    final line = _Line(reader, braces.start + 1, reader._inner(braces));
    for (var at = 0; line[at] != null;) {
      at = statement(line, at, found);
    }
  }

  /// The statements that start from token [from] before token [to], added
  /// to [found], each read up to [limit].
  void statements(int from, int to, int limit, List<ARange> found) {
    final line = _Line(reader, from, limit);
    for (var at = 0; line[at] != null && line[at]!.at < to;) {
      at = statement(line, at, found);
    }
  }

  /// What a function returns after its `=>`, over the tokens [arrow],
  /// added to [found].
  void arrowed(Range arrow, List<ARange> found) {
    expressions.whole(_Line(reader, arrow.start, arrow.end), found);
  }

  /// Where the statement that starts at the first token from [at] that is
  /// not whitespace or a comment ends, reading no further than [limit], or
  /// null where none starts before it.
  int? next(int at, int limit) {
    final line = _Line(reader, at, limit);
    if (line[0] == null) {
      return null;
    }
    return line.end(statement(line, 0, null));
  }

  /// The item after the statement at item [at] of [line], its diagnostics
  /// each over the whole statement, once: a range of what holds a part of
  /// it is read again only with the statement, and so with them.
  int statement(_Line line, int at, List<ARange>? found) {
    final mark = _pending.length;
    final next = _statement(line, at, found);
    final start = line[at]!.at;
    said(mark, start, line.end(next));
    return next;
  }

  /// A diagnostic over the tokens from [start] to [end] for each message
  /// said since there were [mark] of them, each once.
  void said(int mark, int start, int end) {
    if (_pending.length > mark) {
      for (final message in _pending.sublist(mark).toSet()) {
        reader.problems.add(
          ARange.from(span(start, end - start), {'message': literal(message)}),
        );
      }
      _pending.length = mark;
    }
  }

  int _statement(_Line line, int at, List<ARange>? found) {
    final item = line[at]!;
    if (item.pair && item.name == 'braces') {
      if (found != null) {
        block(item.range, found);
      }
      return at + 1;
    }
    final word = line.word(at);
    switch (word) {
      case ';':
        return at + 1;
      case 'if':
        var next = _condition(line, at + 1, found);
        next = _nested(line, next, found);
        if (line.word(next) == 'else') {
          next = _nested(line, next + 1, found);
        }
        return _add(found, 'if', line, at, next);
      case 'for':
        return _for(line, at, at + 1, found);
      case 'await' when line.word(at + 1) == 'for':
        return _for(line, at, at + 2, found);
      case 'while':
        final next = _nested(line, _condition(line, at + 1, found), found);
        return _add(found, 'while', line, at, next);
      case 'do':
        var next = _nested(line, at + 1, found);
        if (line.word(next) == 'while') {
          next = _condition(line, next + 1, found);
        } else {
          _problem(found, 'expected while');
        }
        return _add(found, 'do', line, at, _ended(line, next, found));
      case 'switch':
        var next = _condition(line, at + 1, found);
        if (line.paired(next, 'braces')) {
          if (found != null) {
            _cases(line[next]!.range, found);
          }
          next++;
        } else {
          _problem(found, 'expected {');
        }
        return _add(found, 'switch', line, at, next);
      case 'try':
        return _try(line, at, found);
      case 'return':
        final next = line.mark(at + 1, ';')
            ? at + 1
            : _expression(line, at + 1, found);
        return _add(found, 'return', line, at, _ended(line, next, found));
      case 'break' || 'continue':
        final next = line.naming(at + 1) ? at + 2 : at + 1;
        return _add(found, word!, line, at, _ended(line, next, found));
      case 'yield':
        final from = line.mark(at + 1, '*') ? at + 2 : at + 1;
        final next = _expression(line, from, found, required: true);
        return _add(found, 'yield', line, at, _ended(line, next, found));
      case 'assert':
        var next = at + 1;
        if (line.paired(next, 'parens')) {
          expressions._arguments(line, next, found);
          next++;
        } else {
          _problem(found, 'expected (');
        }
        return _add(found, 'assert', line, at, _ended(line, next, found));
      case 'rethrow':
        return _add(found, 'statement', line, at, _ended(line, at + 1, found));
    }
    if (_unstarting.contains(word)) {
      if (found != null) {
        _problem(found, 'unexpected $word');
      }
      return at + 1;
    }
    if (line.naming(at) && line.mark(at + 1, ':')) {
      _add(found, 'label', line, at, at + 2);
      return _nested(line, at + 2, found);
    }
    if (_local(line, at) case final local?) {
      return local == 'function'
          ? _function(line, at, found)
          : _variable(line, at, found);
    }
    final next = _expression(line, at, found);
    if (next == at) {
      expressions._rest(line, at, found);
      return at + 1;
    }
    return _add(found, 'statement', line, at, _ended(line, next, found));
  }

  /// What the statement at [at] of [line] declares, `function` or
  /// `variable`, or null where it is an expression.
  static String? _local(_Line line, int at) {
    final head = line.metadata(at);
    final word = line.word(head);
    // `late` may name a variable, as `var` and `final` may not.
    if (word == 'var' ||
        word == 'final' ||
        word == 'late' &&
            const {'#name', '#keyword'}.contains(line[head + 1]?.name)) {
      return 'variable';
    }
    if (word == 'await' || word == 'yield') {
      return null;
    }
    if (word == 'const') {
      final typed = line.typed(head + 1);
      return typed > head + 1 && line.naming(typed) ||
              line.naming(head + 1) && line.mark(head + 2, '=')
          ? 'variable'
          : null;
    }
    final typed = line.typed(head);
    // `x as T;` casts, though `as` may name a variable.
    if (typed > head && line.naming(typed) && line.word(typed) != 'as') {
      return line.paired(line.angled(typed + 1), 'parens')
          ? 'function'
          : 'variable';
    }
    // A local function with no return type: a name and its parameters,
    // before its body.
    if (line.naming(head) && line.paired(line.angled(head + 1), 'parens')) {
      var after = line.angled(head + 1) + 1;
      while (const {'async', 'sync'}.contains(line.word(after)) ||
          line.mark(after, '*')) {
        after++;
      }
      if (line.paired(after, 'braces') || line.mark(after, '=>')) {
        return 'function';
      }
    }
    return null;
  }

  /// The local function at [at] of [line], read as a declaration is, and
  /// its body.
  int _function(_Line line, int at, List<ARange>? found) {
    final declared = reader.next(
      line[at]!.at,
      line.limit,
      members: false,
      detailed: found != null,
    )!;
    var next = at;
    while (line[next] != null && line[next]!.at < declared.end) {
      next++;
    }
    if (found != null) {
      found.addAll(declared.ranges);
      if (declared.body case final body?) {
        block(body, found);
      }
      if (declared.arrow case final arrow?) {
        arrowed(arrow, found);
      }
    }
    return next;
  }

  /// The local variable declaration at [at] of [line], to its `;`.
  int _variable(_Line line, int at, List<ARange>? found) {
    final next = _declarators(
      line,
      expressions.annotations(line, at, found),
      found,
    );
    return _add(found, 'variable', line, at, _ended(line, next, found));
  }

  /// The item after the declarators from [at] of [line], after their
  /// modifiers and type: each name, and the expression it is set to; or,
  /// where a pattern stands for the names, the expression after its `=`.
  int _declarators(_Line line, int at, List<ARange>? found) {
    var next = at;
    while (_declaring.contains(line.word(next)) && !line.called(next)) {
      next++;
    }
    final typed = line.typed(next);
    if (typed > next && line.naming(typed)) {
      expressions.type(line, next, found);
      next = typed;
    }
    bool naming(int at) => line.naming(at) || line.called(at);
    // A pattern, such as `(a, b)` or `Point(:x)`, its names declared.
    if (!naming(next) || line.paired(line.angled(next + 1), 'parens')) {
      next = expressions.patterns.pattern(
        line,
        next,
        found,
        _Binding.declaring,
      );
      if (!line.mark(next, '=')) {
        _problem(found, 'expected =');
      }
      while (line[next] != null &&
          !line.mark(next, '=') &&
          !line.mark(next, ';')) {
        next++;
      }
      return line.mark(next, '=')
          ? _expression(line, next + 1, found, required: true)
          : next;
    }
    while (naming(next)) {
      if (found != null) {
        found.add(line.named(next, next));
      }
      next++;
      if (line.mark(next, '=')) {
        next = _expression(line, next + 1, found, required: true);
      }
      if (!line.mark(next, ',') || !naming(next + 1)) {
        break;
      }
      next++;
    }
    return next;
  }

  /// A `for` from [at] of [line], its parts in the parentheses at
  /// [parens].
  int _for(_Line line, int at, int parens, List<ARange>? found) {
    var next = parens;
    if (line.paired(next, 'parens')) {
      if (found != null) {
        _parts(line[next]!.range, found);
      }
      next++;
    } else {
      _problem(found, 'expected (');
    }
    return _add(found, 'for', line, at, _nested(line, next, found));
  }

  /// What the parentheses [parens] of a `for` hold: an initializer, a
  /// condition and updaters, each `;` apart, or what each element is
  /// bound to before `in`, and what it is drawn from after it.
  void _parts(ARange parens, List<ARange> found) {
    final line = _Line(reader, parens.start + 1, reader._inner(parens));
    final marks = [
      for (var at = 0; line[at] != null; at++)
        if (line.mark(at, ';')) at,
    ];
    if (marks.isEmpty) {
      var within = 0;
      while (line[within] != null && line.word(within) != 'in') {
        within++;
      }
      // `final x`, `int x` or `var x`, rather than a pattern or a name.
      if (within >= 2 && line.naming(within - 1)) {
        _add(found, 'variable', line, 0, within);
        var typed = 0;
        while (_declaring.contains(line.word(typed)) && typed < within - 1) {
          typed++;
        }
        if (typed < within - 1) {
          expressions.type(line, typed, found);
        }
        found.add(line.named(within - 1, within - 1));
      }
      // `var (a, b)` or `final [x, ...]`, a pattern its names declared.
      if (_declaring.contains(line.word(0)) && !line.naming(within - 1)) {
        expressions.patterns.pattern(line, 1, found, _Binding.declaring);
      }
      if (line[within] != null) {
        _expression(line, within + 1, found, required: true);
      }
      return;
    }
    if (_local(line, 0) != null) {
      _add(found, 'variable', line, 0, _declarators(line, 0, found));
    } else {
      _expression(line, 0, found);
    }
    if (marks.length > 1) {
      _expression(line, marks[0] + 1, found);
      for (var at = marks[1] + 1; line[at] != null; at++) {
        at = _expression(line, at, found);
      }
    } else {
      _expression(line, marks[0] + 1, found);
    }
  }

  /// A `try` from [at] of [line]: its block, then each `on` or `catch`
  /// clause and the `finally`.
  int _try(_Line line, int at, List<ARange>? found) {
    var next = _block(line, at + 1, found);
    final body = next;
    while (true) {
      final word = line.word(next);
      if (word == 'on' || word == 'catch') {
        final from = next;
        if (word == 'on') {
          next = expressions.type(line, next + 1, found);
        }
        if (line.word(next) == 'catch' && !line.paired(next + 1, 'parens')) {
          next++;
          _problem(found, 'expected (');
        } else if (line.word(next) == 'catch') {
          if (found != null) {
            final caught = line[next + 1]!.range;
            final names = _Line(reader, caught.start + 1, caught.end);
            for (var index = 0; names[index] != null; index += 2) {
              if (names.naming(index)) {
                found.add(names.named(index, index));
              }
            }
          }
          next += 2;
        }
        next = _block(line, next, found);
        _add(found, 'catch', line, from, next);
      } else if (word == 'finally') {
        final from = next;
        next = _block(line, next + 1, found);
        _add(found, 'finally', line, from, next);
      } else {
        if (next == body) {
          _problem(found, 'expected catch or finally');
        }
        return _add(found, 'try', line, at, next);
      }
    }
  }

  /// The block that braces at [at] of [line] should be, and the item after
  /// it.
  int _block(_Line line, int at, List<ARange>? found) {
    if (!line.paired(at, 'braces')) {
      _problem(found, 'expected {');
      return at;
    }
    if (found != null) {
      block(line[at]!.range, found);
    }
    return at + 1;
  }

  /// The members of a switch over the braces [braces]: each `case` or
  /// `default`, with its labels and the statements after it.
  void _cases(ARange braces, List<ARange> found) {
    final line = _Line(reader, braces.start + 1, reader._inner(braces));
    bool member(int at) {
      var next = at;
      while (line.naming(next) && line.mark(next + 1, ':')) {
        next += 2;
      }
      return line.word(next) == 'case' || line.word(next) == 'default';
    }

    var at = 0;
    while (line[at] != null) {
      final from = at;
      if (!member(at)) {
        at = statement(line, at, found);
        continue;
      }
      while (line.word(at) != 'case' && line.word(at) != 'default') {
        _add(found, 'label', line, at, at + 2);
        at += 2;
      }
      final matching = line.word(at) == 'case';
      at++;
      if (matching) {
        at = expressions.patterns.guarded(line, at, found);
      }
      while (line[at] != null && !line.mark(at, ':')) {
        at++;
      }
      if (line[at] == null) {
        _problem(found, 'expected :');
      } else {
        at++;
      }
      while (line[at] != null && !member(at)) {
        at = statement(line, at, found);
      }
      _add(found, 'case', line, from, at);
    }
  }

  /// The parentheses at [at] of [line], and the expression they hold, a
  /// condition or what a switch is over, up to any `case`; and the item
  /// after them.
  int _condition(_Line line, int at, List<ARange>? found) =>
      expressions._condition(line, at, found);

  /// The statement that should start at [at] of [line], as the body of an
  /// `if`, `for`, `while` or `do`, and the item after it.
  int _nested(_Line line, int at, List<ARange>? found) {
    if (line[at] == null) {
      _problem(found, 'expected a statement');
      return at;
    }
    return statement(line, at, found);
  }

  /// The item after the expression from [at] of [line]; where
  /// [required], one of none is a diagnostic.
  int _expression(
    _Line line,
    int at,
    List<ARange>? found, {
    bool required = false,
  }) => required
      ? expressions._required(line, at, found)
      : expressions.expression(line, at, found);

  /// The item after a statement that ends at [at] of [line]: past its
  /// `;`, or, where there is none, at it, with a diagnostic.
  int _ended(_Line line, int at, List<ARange>? found) {
    if (line.mark(at, ';')) {
      return at + 1;
    }
    _problem(found, 'expected ;');
    return at;
  }

  /// A diagnostic saying [message] of the statement being read, where
  /// [found] is given.
  void _problem(List<ARange>? found, String message) {
    if (found != null) {
      _pending.add(message);
    }
  }

  /// A range of [kind] over items [from] to [to] of [line], added to
  /// [found] where it is given; and [to].
  static int _add(
    List<ARange>? found,
    String kind,
    _Line line,
    int from,
    int to,
  ) {
    if (found != null && to > from) {
      final start = line[from]!.at;
      found.add(ranged(start, line.end(to) - start, {'': literal(kind)}));
    }
    return to;
  }
}
