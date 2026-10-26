part of 'dart.dart';

/// The binary operators, each with how tightly it binds: the higher, the
/// tighter. `is` and `as` bind as the relational operators do.
const _binding = {
  '??': 1, '||': 2, '&&': 3, '==': 4, '!=': 4, '<': 5, '>': 5, '<=': 5, //
  '>=': 5, 'is': 5, 'as': 5, '|': 6, '^': 7, '&': 8, '<<': 9, '>>': 9,
  '>>>': 9, '+': 10, '-': 10, '*': 11, '/': 11, '%': 11, '~/': 11,
};

/// The operators that assign.
const _assigning = {
  '=', '*=', '/=', '~/=', '%=', '+=', '-=', '<<=', '>>=', '>>>=', '&=', //
  '^=', '|=', '??=',
};

/// The operators that stand before what they apply to.
const _prefixes = {'-', '!', '~', '++', '--', 'await'};

/// The marks that may stand between the `<` and `>` of type arguments.
const _typing = {'.', ',', '<', '>', '>>', '>>>', '?'};

/// What may follow type arguments that apply to what they follow without
/// calling it, as `List<int>` or `f<int>` does: what ends an expression,
/// or selects from it.
const _instantiating = {
  ';', ',', ':', '.', '?.', '..', '?..', '==', '!=', '=>', //
};

/// Reads expressions, types, parameters, type parameters and annotations
/// from the items of a [_Line], each an element of its kind added to a
/// list where one is given. Where none is, it only finds where each ends,
/// looking no further into the pairs it holds.
///
/// Each function takes the item to start at and gives the item after what
/// it read, or the item it started at where nothing it reads starts there.
final class _Expressions {
  _Expressions(this.statements);

  final _Statements statements;

  _Declarations get reader => statements.reader;

  /// Reads the patterns that expressions and statements hold.
  late final patterns = _Patterns(this);

  /// The line whose `=>` ends a guard rather than following a closure's
  /// parameters, if any.
  _Line? _arrowless;

  /// The expression at [at] of [line], with cascades where [cascade].
  int expression(
    _Line line,
    int at,
    List<ARange>? found, {
    bool cascade = true,
  }) {
    // A pattern assigned to: one that destructures a record, list, map or
    // object, which no expression could be.
    final patterned = line.naming(at) && line.paired(at + 1, 'parens')
        ? at + 2
        : line[at]?.pair == true && line[at]!.name != 'string'
        ? at + 1
        : null;
    if (patterned != null && line.mark(patterned, '=')) {
      patterns.pattern(line, at, found, _Binding.assigning);
      final after = _required(line, patterned + 1, found, cascade: cascade);
      return _add(found, 'assignment', line, at, after, {
        'operator': literal('='),
      });
    }
    var next = _conditional(line, at, found, cascade);
    if (next == at) {
      return at;
    }
    final operator = _mark(line, next);
    if (_assigning.contains(operator)) {
      final after = _required(line, next + 1, found, cascade: cascade);
      return _add(found, 'assignment', line, at, after, {
        'operator': literal(operator!),
      });
    }
    if (!cascade || !line.mark(next, '..') && !line.mark(next, '?..')) {
      return next;
    }
    while (line.mark(next, '..') || line.mark(next, '?..')) {
      final from = next;
      next = _add(found, 'section', line, from, _section(line, from, found));
    }
    return _add(found, 'cascade', line, at, next);
  }

  /// The expression that should start at [at] of [line], with a
  /// diagnostic where none does.
  int _required(
    _Line line,
    int at,
    List<ARange>? found, {
    bool cascade = true,
  }) {
    final next = expression(line, at, found, cascade: cascade);
    if (next == at) {
      statements._problem(found, 'expected an expression');
    }
    return next;
  }

  /// The expression that [line] holds whole, with a diagnostic where
  /// none is, or where more follows it.
  void whole(_Line line, List<ARange>? found) {
    final next = _required(line, 0, found);
    _rest(line, next, found);
  }

  /// A diagnostic where an item stands at [at] of [line], which should be
  /// past the last. It says what the item is, a keyword or a mark as it is
  /// written and a name or a number as such: typing in one keeps what was
  /// read before, its diagnostics among it.
  void _rest(_Line line, int at, List<ARange>? found) {
    // A mark that closes nothing is said to by the pairing.
    if (line[at] case final item?
        when !const {')', ']', '}'}.contains(item.name)) {
      final said = switch (item.name) {
        _ when item.pair => item.name,
        '#name' => 'name',
        '#number' => 'number',
        _ => line.word(at),
      };
      statements._problem(found, 'unexpected $said');
    }
  }

  /// The cascade section whose `..` is at [at] of [line]: a selector, the
  /// selectors after it, and what it assigns.
  int _section(_Line line, int at, List<ARange>? found) {
    var next = at + 1;
    if (line.paired(next, 'brackets')) {
      _index(line, next, found);
      next = _add(found, 'index', line, at, next + 1);
    } else if (_worded(line, next)) {
      next = _selected(line, at, next + 1, found);
    } else {
      statements._problem(found, 'expected a name');
      return next;
    }
    next = _selectors(line, at, next, found);
    final operator = _mark(line, next);
    if (_assigning.contains(operator)) {
      final after = _required(line, next + 1, found, cascade: false);
      return _add(found, 'assignment', line, at, after, {
        'operator': literal(operator!),
      });
    }
    return next;
  }

  int _conditional(_Line line, int at, List<ARange>? found, bool cascade) {
    final next = _binary(line, at, 1, found);
    if (next == at || !line.mark(next, '?')) {
      return next;
    }
    final then = _required(line, next + 1, found, cascade: false);
    if (!line.mark(then, ':')) {
      statements._problem(found, 'expected :');
      return _add(found, 'conditional', line, at, then);
    }
    final otherwise = _required(line, then + 1, found, cascade: false);
    return _add(found, 'conditional', line, at, otherwise);
  }

  /// The operands and operators from [at] of [line] that bind at least as
  /// tightly as [least], each operator taking what is before it.
  int _binary(_Line line, int at, int least, List<ARange>? found) {
    var next = _unary(line, at, found);
    if (next == at) {
      return at;
    }
    while (true) {
      final operator = line[next]?.pair == false ? line.word(next) : null;
      final binding = _binding[operator];
      if (binding == null || binding < least) {
        return next;
      }
      if (operator == 'is' || operator == 'as') {
        final from = operator == 'is' && line.mark(next + 1, '!')
            ? next + 2
            : next + 1;
        final after = type(line, from, found, ambiguous: true);
        if (after == from) {
          statements._problem(found, 'expected a type');
        }
        next = _add(found, operator!, line, at, after);
        continue;
      }
      final right = _binary(line, next + 1, binding + 1, found);
      if (right == next + 1) {
        statements._problem(found, 'expected an expression');
      }
      next = _add(found, 'binary', line, at, right, {
        'operator': literal(operator!),
      });
    }
  }

  int _unary(_Line line, int at, List<ARange>? found) {
    final operator = line[at]?.pair == false ? line.word(at) : null;
    if (_prefixes.contains(operator) &&
        (operator != 'await' || _starts(line, at + 1))) {
      final next = _unary(line, at + 1, found);
      if (next == at + 1) {
        statements._problem(found, 'expected an expression');
      }
      return _add(found, 'prefix', line, at, next, {
        'operator': literal(operator!),
      });
    }
    final next = _primary(line, at, found);
    return next == at ? at : _selectors(line, at, next, found);
  }

  /// The selectors from [from] of [line] after what starts at [at]: each
  /// call, index, property, `!`, and an `++` or `--` last.
  int _selectors(_Line line, int at, int from, List<ARange>? found) {
    var next = from;
    while (true) {
      final item = line[next];
      if (item == null) {
        return next;
      }
      if (item.pair) {
        if (item.name == 'parens') {
          _arguments(line, next, found);
          next = _add(found, 'call', line, at, next + 1);
        } else if (item.name == 'brackets') {
          _index(line, next, found);
          next = _add(found, 'index', line, at, next + 1);
        } else {
          return next;
        }
        continue;
      }
      switch (item.name) {
        case '.' || '?.':
          if (!_worded(line, next + 1)) {
            statements._problem(found, 'expected a name');
            return next + 1;
          }
          next = _selected(line, at, next + 2, found);
        case '!':
          next = _add(found, 'postfix', line, at, next + 1, {
            'operator': literal('!'),
          });
        case '++' || '--':
          return _add(found, 'postfix', line, at, next + 1, {
            'operator': literal(item.name),
          });
        case '<':
          final closed = _arguable(line, next);
          if (closed == null) {
            return next;
          }
          _typed(line, next, closed, found);
          if (line.paired(closed, 'parens')) {
            _arguments(line, closed, found);
            next = _add(found, 'call', line, at, closed + 1);
          } else {
            next = _add(found, 'instantiation', line, at, closed);
          }
        // `a?[i]`, the `?` against the brackets, rather than `a ? [i] : b`.
        case '?'
            when line.paired(next + 1, 'brackets') &&
                line[next + 1]!.at == item.end:
          _index(line, next + 1, found);
          next = _add(found, 'index', line, at, next + 2);
        default:
          return next;
      }
    }
  }

  /// What a name selected before [after] of [line], from what starts at
  /// [at], makes: a call where arguments follow it, perhaps after type
  /// arguments, and otherwise a property.
  int _selected(_Line line, int at, int after, List<ARange>? found) {
    final closed = _arguable(line, after);
    if (closed != null && line.paired(closed, 'parens')) {
      _typed(line, after, closed, found);
      _arguments(line, closed, found);
      return _add(found, 'call', line, at, closed + 1);
    }
    if (line.paired(after, 'parens')) {
      _arguments(line, after, found);
      return _add(found, 'call', line, at, after + 1);
    }
    return _add(found, 'property', line, at, after);
  }

  int _primary(_Line line, int at, List<ARange>? found) {
    final item = line[at];
    if (item == null) {
      return at;
    }
    if (item.pair) {
      return switch (item.name) {
        'parens' => _parenthesized(line, at, found),
        'brackets' => _add(found, 'list', line, at, _listed(line, at, found)),
        'braces' => _collected(line, at, at, null, found),
        'string' => _strings(line, at, found),
        _ => at,
      };
    }
    switch (item.name) {
      case '#number':
        return at + 1;
      case '#name':
        return _created(line, at, found) ?? at + 1;
      case '<':
        return _generic(line, at, at, found);
      case '[]':
        return _add(found, 'list', line, at, at + 1);
      case '#':
        return _symbol(line, at, found);
      // A shorthand for a static member of the type the context expects.
      case '.' when _worded(line, at + 1):
        return _selected(line, at, at + 2, found);
    }
    if (item.name != '#keyword') {
      return at;
    }
    switch (line.word(at)) {
      case 'this' || 'super' || 'null' || 'true' || 'false':
        return at + 1;
      case 'new':
        return _construct(line, at, found, const {});
      case 'const':
        return _constant(line, at, found);
      case 'throw':
        final next = _required(line, at + 1, found);
        return _add(found, 'throw', line, at, next);
      case 'switch':
        return _switch(line, at, found);
    }
    // A word Dart builds in names what it is called, as `late` or
    // `factory` may.
    return _reserved.contains(line.word(at))
        ? at
        : _created(line, at, found) ?? at + 1;
  }

  /// What `const` at [at] of [line] makes constant: a collection, a record
  /// or a call.
  int _constant(_Line line, int at, List<ARange>? found) {
    final next = at + 1;
    final item = line[next];
    if (item == null) {
      statements._problem(found, 'expected an expression');
      return next;
    }
    if (item.pair && item.name == 'brackets' || item.name == '[]') {
      final after = item.pair ? _listed(line, next, found) : next + 1;
      return _add(found, 'list', line, at, after, _const);
    }
    if (item.pair && item.name == 'braces') {
      return _collected(line, at, next, null, found, _const);
    }
    if (item.pair && item.name == 'parens') {
      _record(line, next, found, always: true);
      return _add(found, 'record', line, at, next + 1, _const);
    }
    if (item.name == '<') {
      return _generic(line, at, next, found, _const);
    }
    return _construct(line, at, found, _const);
  }

  /// The call that `new` or `const` at [at] of [line] makes of the
  /// constructor named after it.
  int _construct(
    _Line line,
    int at,
    List<ARange>? found,
    Map<String, Value> attributes,
  ) {
    final next = constructor(line, at + 1, found);
    if (next == at + 1) {
      statements._problem(found, 'expected a type');
      return next;
    }
    if (!line.paired(next, 'parens')) {
      statements._problem(found, 'expected (');
      return _add(found, 'call', line, at, next, attributes);
    }
    _arguments(line, next, found);
    return _add(found, 'call', line, at, next + 1, attributes);
  }

  /// The constructor named at [at] of [line]: a type of a name, or of a
  /// prefix and a name, with any type arguments, then the constructor's
  /// own name, where a third name or type arguments leave one.
  int constructor(_Line line, int at, List<ARange>? found) {
    if (!line.naming(at)) {
      return at;
    }
    var end = at + 1;
    if (line.mark(end, '.') && line.naming(end + 1)) {
      end += 2;
    }
    if (line.mark(end, '<')) {
      final closed = line.angled(end);
      if (closed > end) {
        _typed(line, end, closed, found);
        end = closed;
      }
    }
    if (end - at > 1) {
      _add(found, 'type', line, at, end);
    }
    return line.mark(end, '.') && _worded(line, end + 1) ? end + 2 : end;
  }

  /// The call of a constructor that a name at [at] of [line] makes,
  /// written with type arguments and a constructor's name, as
  /// `List<int>.filled(...)` or `p.A<int>.b(...)` is; null where it makes
  /// none.
  int? _created(_Line line, int at, List<ARange>? found) {
    var typed = at + 1;
    if (line.mark(typed, '.') &&
        line.naming(typed + 1) &&
        line.mark(typed + 2, '<')) {
      typed += 2;
    }
    final closed = _arguable(line, typed);
    if (closed == null ||
        !line.mark(closed, '.') ||
        !_worded(line, closed + 1) ||
        !line.paired(closed + 2, 'parens')) {
      return null;
    }
    _typed(line, typed, closed, found);
    _add(found, 'type', line, at, closed);
    _arguments(line, closed + 2, found);
    return _add(found, 'call', line, at, closed + 3);
  }

  /// What starts with type arguments at [from] of [line], from [at] where
  /// `const` stands before them: a collection, or a closure's type
  /// parameters.
  int _generic(
    _Line line,
    int at,
    int from,
    List<ARange>? found, [
    Map<String, Value> attributes = const {},
  ]) {
    final closed = line.angled(from);
    if (closed == from) {
      return at;
    }
    final item = line[closed];
    if (item != null && item.pair && item.name == 'parens') {
      return _closure(line, from, found);
    }
    final count = _typed(line, from, closed, found);
    if (item != null &&
        (item.name == '[]' || item.pair && item.name == 'brackets')) {
      final after = item.pair ? _listed(line, closed, found) : closed + 1;
      return _add(found, 'list', line, at, after, attributes);
    }
    if (item != null && item.pair && item.name == 'braces') {
      return _collected(line, at, closed, count, found, attributes);
    }
    statements._problem(found, 'expected [ or {');
    return closed;
  }

  /// The parentheses at [at] of [line]: a closure's parameters where a
  /// body follows them, and otherwise a record or an expression.
  int _parenthesized(_Line line, int at, List<ARange>? found) {
    var after = at + 1;
    while (const {'async', 'sync'}.contains(line.word(after)) ||
        line.mark(after, '*')) {
      after++;
    }
    if (line.paired(after, 'braces') ||
        line.mark(after, '=>') && !identical(line, _arrowless)) {
      return _closure(line, at, found);
    }
    if (_record(line, at, found)) {
      _add(found, 'record', line, at, at + 1);
    }
    return at + 1;
  }

  /// Whether the parentheses at [at] of [line] hold a record, as none,
  /// a `,` or a named field says they do, reading what they hold; any
  /// that do where [always].
  bool _record(_Line line, int at, List<ARange>? found, {bool always = false}) {
    if (found == null) {
      return always;
    }
    final inner = _inside(line, at);
    if (inner[0] == null) {
      return true;
    }
    var record = always;
    var next = 0;
    while (inner[next] != null) {
      final from = next;
      if (_labeled(inner, next)) {
        record = true;
        next = _required(inner, next + 2, found);
        _add(found, 'argument', inner, from, next);
      } else {
        next = _required(inner, next, found);
      }
      if (!inner.mark(next, ',')) {
        _rest(inner, next, found);
        break;
      }
      record = true;
      next++;
    }
    return record;
  }

  /// The arguments of a call in the parentheses at [at] of [line]: each
  /// expression, and each named one an `argument`.
  void _arguments(_Line line, int at, List<ARange>? found) {
    if (found == null) {
      return;
    }
    final inner = _inside(line, at);
    var next = 0;
    while (inner[next] != null) {
      final from = next;
      if (_labeled(inner, next)) {
        next = _required(inner, next + 2, found);
        _add(found, 'argument', inner, from, next);
      } else {
        next = _required(inner, next, found);
      }
      if (!inner.mark(next, ',')) {
        _rest(inner, next, found);
        return;
      }
      next++;
    }
  }

  /// What indexes in the brackets at [at] of [line].
  void _index(_Line line, int at, List<ARange>? found) {
    if (found != null) {
      whole(_inside(line, at), found);
    }
  }

  /// Whether a name and a `:` start at [at] of [line], as a named
  /// argument or field does.
  static bool _labeled(_Line line, int at) =>
      _worded(line, at) && line.mark(at + 1, ':');

  /// The list over the brackets at [at] of [line], and the item after it.
  int _listed(_Line line, int at, List<ARange>? found) {
    if (found != null) {
      _elements(_inside(line, at), found);
    }
    return at + 1;
  }

  /// The set or map from [at] of [line] over the braces at [braces], a map
  /// where [count] type arguments are two, or, with none, where it holds
  /// an entry or holds no value.
  int _collected(
    _Line line,
    int at,
    int braces,
    int? count,
    List<ARange>? found, [
    Map<String, Value> attributes = const {},
  ]) {
    final held = found == null ? 0 : _elements(_inside(line, braces), found);
    final mapped = count == null
        ? held & _entry != 0 || held & _value == 0
        : count == 2;
    return _add(
      found,
      mapped ? 'map' : 'set',
      line,
      at,
      braces + 1,
      attributes,
    );
  }

  /// What the elements of a collection, over [line], hold, as bits of
  /// [_entry] and [_value].
  int _elements(_Line line, List<ARange> found) {
    var held = 0;
    var next = 0;
    while (line[next] != null) {
      final (after, kind) = _element(line, next, found);
      held |= kind;
      if (after == next) {
        _rest(line, next, found);
        break;
      }
      next = after;
      if (!line.mark(next, ',')) {
        _rest(line, next, found);
        break;
      }
      next++;
    }
    return held;
  }

  /// An element of a collection holds an entry.
  static const _entry = 1;

  /// An element of a collection holds a value other than an entry.
  static const _value = 2;

  /// The element of a collection at [at] of [line], and what it holds.
  (int, int) _element(_Line line, int at, List<ARange> found) {
    final word = line.word(at);
    if (word == '...' || word == '...?') {
      final next = _required(line, at + 1, found);
      return (_add(found, 'spread', line, at, next), 0);
    }
    if (word == 'if') {
      var next = _condition(line, at + 1, found);
      final (then, held) = _nested(line, next, found);
      next = then;
      var kind = held;
      if (line.word(next) == 'else') {
        final (otherwise, more) = _nested(line, next + 1, found);
        next = otherwise;
        kind |= more;
      }
      return (_add(found, 'if', line, at, next), kind);
    }
    if (word == 'for' || word == 'await' && line.word(at + 1) == 'for') {
      var next = word == 'for' ? at + 1 : at + 2;
      if (line.paired(next, 'parens')) {
        statements._parts(line[next]!.range, found);
        next++;
      } else {
        statements._problem(found, 'expected (');
      }
      final (body, held) = _nested(line, next, found);
      return (_add(found, 'for', line, at, body), held);
    }
    // A key or value that is left out where it is null.
    final aware = line.mark(at, '?');
    final key = _required(line, aware ? at + 1 : at, found);
    if (!line.mark(key, ':')) {
      return (aware ? _add(found, 'aware', line, at, key) : key, _value);
    }
    final value = line.mark(key + 1, '?') ? key + 2 : key + 1;
    final next = _required(line, value, found);
    return (_add(found, 'entry', line, at, next), _entry);
  }

  /// The element that should start at [at] of [line], after an `if`,
  /// `else` or `for`.
  (int, int) _nested(_Line line, int at, List<ARange> found) {
    if (line[at] == null) {
      statements._problem(found, 'expected an expression');
      return (at, 0);
    }
    return _element(line, at, found);
  }

  /// The parentheses at [at] of [line] and the condition they hold, with
  /// any `case`, its pattern and its guard; and the item after them.
  int _condition(_Line line, int at, List<ARange>? found) {
    if (!line.paired(at, 'parens')) {
      statements._problem(found, 'expected (');
      return at;
    }
    if (found != null) {
      final inner = _inside(line, at);
      var next = _required(inner, 0, found);
      if (inner.word(next) == 'case') {
        next = patterns.guarded(inner, next + 1, found);
      }
      _rest(inner, next, found);
    }
    return at + 1;
  }

  /// The strings from the one at [at] of [line], one after another, and
  /// the expressions their interpolations hold.
  int _strings(_Line line, int at, List<ARange>? found) {
    var next = at;
    while (line.paired(next, 'string')) {
      if (found != null) {
        final string = _Line(reader, line[next]!.at + 1, line[next]!.end);
        for (var index = 0; string[index] != null; index++) {
          if (string.paired(index, 'interpolation')) {
            whole(_inside(string, index), found);
          }
        }
      }
      next++;
    }
    return next - at > 1 ? _add(found, 'strings', line, at, next) : next;
  }

  /// The symbol at [at] of [line]: `#` and the names after it, `.` apart,
  /// or an operator.
  int _symbol(_Line line, int at, List<ARange>? found) {
    var next = at + 1;
    if (_worded(line, next)) {
      next++;
      while (line.mark(next, '.') && _worded(line, next + 1)) {
        next += 2;
      }
    } else if (line[next]?.pair == false) {
      next++;
    }
    return _add(found, 'symbol', line, at, next);
  }

  /// The switch expression at [at] of [line]: what it is over, then each
  /// case, a pattern and its guard, `=>` and its value.
  int _switch(_Line line, int at, List<ARange>? found) {
    final next = _condition(line, at + 1, found);
    if (!line.paired(next, 'braces')) {
      statements._problem(found, 'expected {');
      return _add(found, 'switch', line, at, next);
    }
    if (found != null) {
      final cases = _inside(line, next);
      var index = 0;
      while (cases[index] != null) {
        final from = index;
        index = patterns.guarded(cases, index, found, arm: true);
        if (!cases.mark(index, '=>')) {
          statements._problem(found, 'expected =>');
        }
        while (cases[index] != null &&
            !cases.mark(index, '=>') &&
            !cases.mark(index, ',')) {
          index++;
        }
        if (cases.mark(index, '=>')) {
          index = _required(cases, index + 1, found);
        }
        _add(found, 'case', cases, from, index);
        if (!cases.mark(index, ',')) {
          _rest(cases, index, found);
          break;
        }
        index++;
      }
    }
    return _add(found, 'switch', line, at, next + 1);
  }

  /// The closure at [at] of [line]: any type parameters, its parameters,
  /// any `async`, `sync` and `*`, and its block or `=>` and what it gives.
  int _closure(_Line line, int at, List<ARange>? found) {
    var next = at;
    if (line.mark(next, '<')) {
      final closed = line.angled(next);
      generics(line, next, closed, found);
      next = closed;
    }
    if (found != null) {
      parameters(line[next]!.range, found);
    }
    next++;
    while (const {'async', 'sync'}.contains(line.word(next)) ||
        line.mark(next, '*')) {
      next++;
    }
    if (line.paired(next, 'braces')) {
      if (found != null) {
        statements.block(line[next]!.range, found);
      }
      next++;
    } else if (line.mark(next, '=>')) {
      next = _required(line, next + 1, found);
    } else {
      statements._problem(found, 'expected {');
    }
    return _add(found, 'closure', line, at, next);
  }

  /// The type at [at] of [line]: a name, perhaps after a prefix, with
  /// any type arguments; `void`; a record's fields in parentheses; or a
  /// function type, with what it returns before `Function`. Each is
  /// nullable with a `?` after it, except where [ambiguous] and the `?`
  /// may start the rest of a conditional, after `is` or `as`.
  ///
  /// Within type arguments whose `>` is at [within], a type whose own type
  /// arguments end with the same token, as `>>` ends two, ends there.
  int type(
    _Line line,
    int at,
    List<ARange>? found, {
    bool ambiguous = false,
    int? within,
  }) {
    var next = at;
    final word = line.word(at);
    final returning =
        word != 'Function' ||
        !line.mark(at + 1, '<') && !line.paired(at + 1, 'parens');
    if (returning) {
      if (word == 'void') {
        next++;
      } else if (line.paired(at, 'parens')) {
        if (found != null) {
          _fields(_inside(line, at), found);
        }
        next++;
      } else if (line.naming(at) || word == 'Function') {
        next++;
        if (line.mark(next, '.') && line.naming(next + 1)) {
          next += 2;
        }
        if (line.mark(next, '<')) {
          final closed = line.angled(next);
          if (closed > next) {
            _typed(line, next, closed, found);
            next = closed;
          }
        }
      } else {
        return at;
      }
      if (within != null && next > within) {
        return _add(found, 'type', line, at, next);
      }
      if (_nullable(line, next, ambiguous)) {
        next++;
      }
      if (next - at > 1 || line.paired(at, 'parens')) {
        _add(found, 'type', line, at, next);
      }
    }
    while (line.word(next) == 'Function') {
      next++;
      if (line.mark(next, '<')) {
        final closed = line.angled(next);
        generics(line, next, closed, found);
        next = closed;
      }
      if (!line.paired(next, 'parens')) {
        return _add(found, 'type', line, at, next);
      }
      if (found != null) {
        parameters(line[next]!.range, found, typing: true);
      }
      next++;
      if (_nullable(line, next, ambiguous)) {
        next++;
      }
      _add(found, 'type', line, at, next);
    }
    return next;
  }

  /// Whether a `?` at [at] of [line] makes a type nullable: where it is
  /// [ambiguous], only where what follows it could not start an
  /// expression.
  static bool _nullable(_Line line, int at, bool ambiguous) =>
      line.mark(at, '?') && (!ambiguous || !_starts(line, at + 1));

  /// The fields of a record type over [line]: each a type and perhaps a
  /// name, the named ones in braces.
  void _fields(_Line line, List<ARange> found) {
    var next = 0;
    while (line[next] != null) {
      if (line.paired(next, 'braces')) {
        _fields(_inside(line, next), found);
        next++;
      } else {
        next = type(line, annotations(line, next, found), found);
        if (line.naming(next)) {
          next++;
        }
      }
      if (!line.mark(next, ',')) {
        _rest(line, next, found);
        return;
      }
      next++;
    }
  }

  /// The types of the type arguments from the `<` at [at] of [line] to
  /// the item [closed] after their `>`, and how many there are.
  int _typed(_Line line, int at, int closed, List<ARange>? found) {
    var count = 0;
    var next = at + 1;
    while (next < closed) {
      final after = type(line, next, found, within: closed - 1);
      count++;
      if (after == next || !line.mark(after, ',')) {
        break;
      }
      next = after + 1;
    }
    return count;
  }

  /// The item after the type arguments at [at] of [line] where what they
  /// hold may be types and what follows makes them type arguments: a
  /// call's arguments, what selects from them, or what ends an expression.
  /// Null otherwise.
  int? _arguable(_Line line, int at) {
    if (!line.mark(at, '<')) {
      return null;
    }
    final closed = line.angled(at);
    if (closed == at) {
      return null;
    }
    for (var index = at + 1; index < closed - 1; index++) {
      final item = line[index]!;
      if (item.pair
          ? item.name != 'parens'
          : !_typing.contains(item.name) &&
                !line.naming(index) &&
                !const {'void', 'Function'}.contains(line.word(index))) {
        return null;
      }
    }
    final after = line[closed];
    return after == null ||
            after.pair && after.name == 'parens' ||
            !after.pair && _instantiating.contains(after.name)
        ? closed
        : null;
  }

  /// The formal parameters in [parens]: each with its annotations,
  /// modifiers, type, name and default value, and those in the brackets or
  /// braces of optional and named ones. Within a function type, where
  /// [typing], a parameter may be a type alone.
  void parameters(ARange parens, List<ARange> found, {bool typing = false}) {
    final line = _Line(reader, parens.start + 1, reader._inner(parens));
    var next = 0;
    while (line[next] != null) {
      if (line.paired(next, 'brackets') || line.paired(next, 'braces')) {
        parameters(line[next]!.range, found, typing: typing);
        next++;
      } else {
        final after = _parameter(line, next, found, typing);
        if (after == next) {
          _rest(line, next, found);
          return;
        }
        next = after;
      }
      if (!line.mark(next, ',')) {
        _rest(line, next, found);
        return;
      }
      next++;
    }
  }

  int _parameter(_Line line, int at, List<ARange> found, bool typing) {
    var next = annotations(line, at, found);
    while (const {
          'required', 'covariant', 'final', 'var', 'const', //
        }.contains(line.word(next)) &&
        !line.called(next)) {
      next++;
    }
    final typed = line.typed(next);
    if (typed > next &&
        (line.naming(typed) ||
            line.called(typed) ||
            const {'this', 'super'}.contains(line.word(typed)) ||
            typing)) {
      type(line, next, found);
      next = typed;
    }
    if (const {'this', 'super'}.contains(line.word(next)) &&
        line.mark(next + 1, '.')) {
      next += 2;
    }
    if (line.naming(next) || line.called(next)) {
      found.add(line.named(next, next));
      next++;
    }
    // A parameter that is a function, with its own parameters.
    if (line.mark(next, '<')) {
      final closed = line.angled(next);
      generics(line, next, closed, found);
      next = closed;
    }
    if (line.paired(next, 'parens')) {
      parameters(line[next]!.range, found);
      next++;
      if (line.mark(next, '?')) {
        next++;
      }
    }
    if (line.mark(next, '=') || line.mark(next, ':')) {
      next = _required(line, next + 1, found);
    }
    return _add(found, 'parameter', line, at, next);
  }

  /// The type parameters from the `<` at [at] of [line] to the item
  /// [closed] after their `>`: each a `generic` with its name and bound.
  void generics(_Line line, int at, int closed, List<ARange>? found) {
    if (found == null) {
      return;
    }
    var next = at + 1;
    while (next < closed) {
      final from = next;
      next = annotations(line, next, found);
      if (line.naming(next) || line.called(next)) {
        found.add(line.named(next, next));
        next++;
      }
      if (line.word(next) == 'extends') {
        next = type(line, next + 1, found, within: closed - 1);
      }
      if (next == from) {
        break;
      }
      _add(found, 'generic', line, from, next);
      if (!line.mark(next, ',')) {
        break;
      }
      next++;
    }
  }

  /// The annotations from [at] of [line], each with its arguments.
  int annotations(_Line line, int at, List<ARange>? found) {
    var next = at;
    while (line.mark(next, '@')) {
      final from = next;
      next = line.annotation(next);
      if (found != null) {
        for (var index = from + 1; index < next; index++) {
          if (line.mark(index, '<')) {
            final closed = line.angled(index);
            _typed(line, index, closed, found);
            index = closed - 1;
          } else if (line.paired(index, 'parens')) {
            _arguments(line, index, found);
          }
        }
      }
      _add(found, 'annotation', line, from, next);
    }
    return next;
  }

  /// A [_Line] over what the pair at [at] of [line] holds.
  _Line _inside(_Line line, int at) {
    final pair = line[at]!.range;
    return _Line(reader, pair.start + 1, reader._inner(pair));
  }

  /// Whether the item at [at] of [line] is a word: a name or a keyword,
  /// as what is selected by `.` may be.
  static bool _worded(_Line line, int at) {
    final item = line[at];
    return item != null &&
        !item.pair &&
        (item.name == '#name' || item.name == '#keyword');
  }

  /// The mark at [at] of [line], if a mark is there.
  static String? _mark(_Line line, int at) {
    final item = line[at];
    return item == null || item.pair || item.name.startsWith('#')
        ? null
        : item.name;
  }

  /// Whether an expression may start at [at] of [line].
  static bool _starts(_Line line, int at) {
    final item = line[at];
    if (item == null) {
      return false;
    }
    if (item.pair) {
      return item.name != 'interpolation';
    }
    return switch (item.name) {
      '#name' || '#number' => true,
      '#keyword' =>
        !_reserved.contains(line.word(at)) ||
            const {
              'this',
              'super',
              'null',
              'true',
              'false',
              'new',
              'const',
              'throw', //
              'switch', 'await', 'void', 'Function',
            }.contains(line.word(at)),
      _ => const {
        '-', '!', '~', '++', '--', '<', '[]', '#', '.', '...', '...?', //
      }.contains(item.name),
    };
  }

  /// A range of [kind] over items [from] to [to] of [line], saying
  /// [attributes], added to [found] where it is given; and [to].
  static int _add(
    List<ARange>? found,
    String kind,
    _Line line,
    int from,
    int to, [
    Map<String, Value> attributes = const {},
  ]) {
    if (found != null && to > from) {
      final start = line[from]!.at;
      found.add(
        ranged(start, line.end(to) - start, {'': literal(kind), ...attributes}),
      );
    }
    return to;
  }
}

/// What a `const` element says.
final _const = {'const': literal('const')};
