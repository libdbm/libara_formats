part of 'dart.dart';

/// What a pattern does with a name standing alone in it: matches the
/// constant it names, declares a variable of it, or assigns to it.
enum _Binding { matching, declaring, assigning }

/// The relational operators a pattern may start with.
const _relating = {'==', '!=', '<', '>', '<=', '>='};

/// Reads patterns, each of more than one token a `pattern` saying its
/// `form`, with the names its variables declare and the expressions and
/// types it holds, through [_Expressions].
final class _Patterns {
  _Patterns(this.expressions);

  final _Expressions expressions;

  _Statements get statements => expressions.statements;

  /// The pattern at [at] of [line] that a `case` matches, and the guard
  /// after its `when`, which, in an arm of a switch expression, where
  /// [arm], the arm's `=>` ends: `(...) =>` there is no closure.
  int guarded(_Line line, int at, List<ARange>? found, {bool arm = false}) {
    final next = pattern(line, at, found, _Binding.matching);
    if (next == at) {
      statements._problem(found, 'expected a pattern');
    }
    if (line.word(next) != 'when') {
      return next;
    }
    final outer = expressions._arrowless;
    expressions._arrowless = arm ? line : null;
    final after = expressions._required(line, next + 1, found, cascade: false);
    expressions._arrowless = outer;
    return after;
  }

  /// The pattern at [at] of [line], its names bound as [binding] says.
  int pattern(_Line line, int at, List<ARange>? found, _Binding binding) {
    var next = _and(line, at, found, binding);
    while (next > at && line.mark(next, '||')) {
      next = _form(
        found,
        'logical',
        line,
        at,
        _required(line, next + 1, found, binding, _and),
      );
    }
    return next;
  }

  int _and(_Line line, int at, List<ARange>? found, _Binding binding) {
    var next = _unary(line, at, found, binding);
    while (next > at && line.mark(next, '&&')) {
      next = _form(
        found,
        'logical',
        line,
        at,
        _required(line, next + 1, found, binding, _unary),
      );
    }
    return next;
  }

  /// What [read] reads at [at] of [line], with a diagnostic where it
  /// reads nothing.
  int _required(
    _Line line,
    int at,
    List<ARange>? found,
    _Binding binding,
    int Function(_Line, int, List<ARange>?, _Binding) read,
  ) {
    final next = read(line, at, found, binding);
    if (next == at) {
      statements._problem(found, 'expected a pattern');
    }
    return next;
  }

  /// A relational pattern, or a primary one and each `?`, `!` and cast
  /// after it.
  int _unary(_Line line, int at, List<ARange>? found, _Binding binding) {
    if (_relating.contains(_Expressions._mark(line, at))) {
      final next = expressions._binary(line, at + 1, 6, found);
      if (next == at + 1) {
        statements._problem(found, 'expected an expression');
      }
      return _form(found, 'relational', line, at, next);
    }
    var next = _primary(line, at, found, binding);
    if (next == at) {
      return at;
    }
    while (true) {
      if (line.mark(next, '?')) {
        next = _form(found, 'check', line, at, next + 1);
      } else if (line.mark(next, '!')) {
        next = _form(found, 'assert', line, at, next + 1);
      } else if (line.word(next) == 'as') {
        final after = expressions.type(line, next + 1, found);
        if (after == next + 1) {
          statements._problem(found, 'expected a type');
        }
        next = _form(found, 'cast', line, at, after);
      } else {
        return next;
      }
    }
  }

  int _primary(_Line line, int at, List<ARange>? found, _Binding binding) {
    final item = line[at];
    if (item == null) {
      return at;
    }
    if (item.pair) {
      return switch (item.name) {
        'parens' => _record(line, at, found, binding),
        'brackets' => _listed(line, at, at, found, binding),
        'braces' => _mapped(line, at, at, found, binding),
        'string' => _constant(
          found,
          line,
          at,
          expressions._strings(line, at, found),
        ),
        _ => at,
      };
    }
    final word = line.word(at);
    switch (item.name) {
      case '[]':
        return _form(found, 'list', line, at, at + 1);
      case '<':
        final closed = line.angled(at);
        if (closed == at) {
          return at;
        }
        expressions._typed(line, at, closed, found);
        if (line.paired(closed, 'braces')) {
          return _mapped(line, at, closed, found, binding);
        }
        if (line[closed]?.name == '[]') {
          return _form(found, 'list', line, at, closed + 1);
        }
        return _listed(line, at, closed, found, binding);
      case '-' || '#':
        return _constant(found, line, at, expressions._unary(line, at, found));
      case '#number':
        return at + 1;
    }
    if (word == 'var' || word == 'final') {
      var next = at + 1;
      final typed = line.typed(next);
      if (word == 'final' && typed > next && _named(line, typed)) {
        expressions.type(line, next, found);
        next = typed;
      }
      return _variable(line, at, next, found);
    }
    if (word == 'const') {
      final next = expressions._unary(line, at + 1, found);
      if (next == at + 1) {
        statements._problem(found, 'expected an expression');
      }
      return _constant(found, line, at, next);
    }
    if (const {'null', 'true', 'false'}.contains(word)) {
      return at + 1;
    }
    if (item.name != '#name' &&
        (item.name != '#keyword' || _reserved.contains(word))) {
      return at;
    }
    // A type and a name: a variable, typed.
    final typed = line.typed(at);
    if (typed > at && _named(line, typed)) {
      expressions.type(line, at, found);
      return _variable(line, at, typed, found);
    }
    // A type and its fields: an object.
    var after = at + 1;
    if (line.mark(after, '.') && line.naming(after + 1)) {
      after += 2;
    }
    after = line.angled(after);
    if (line.paired(after, 'parens')) {
      expressions.type(line, at, found);
      if (found != null) {
        _fields(expressions._inside(line, after), found, binding);
      }
      return _form(found, 'object', line, at, after + 1);
    }
    if (line[at + 1]?.name != '.' && binding != _Binding.matching) {
      if (binding == _Binding.declaring && word != '_' && found != null) {
        found.add(line.named(at, at));
      }
      return at + 1;
    }
    if (word == '_') {
      return at + 1;
    }
    // A constant named, perhaps after what holds it.
    var next = at + 1;
    while (line.mark(next, '.') && _Expressions._worded(line, next + 1)) {
      next = _Expressions._add(found, 'property', line, at, next + 2);
    }
    return _constant(found, line, at, next);
  }

  /// Whether the item at [at] of [line] names a variable after its type,
  /// rather than a guard or a cast following the pattern.
  static bool _named(_Line line, int at) {
    final item = line[at];
    return item != null &&
        !item.pair &&
        (item.name == '#name' ||
            item.name == '#keyword' &&
                !_reserved.contains(line.word(at)) &&
                !const {'when', 'as'}.contains(line.word(at)));
  }

  /// The variable that the name at [name] of [line] declares, from [at]
  /// where a keyword or a type stands before it: a wildcard where the
  /// name is `_`.
  int _variable(_Line line, int at, int name, List<ARange>? found) {
    if (!_named(line, name)) {
      statements._problem(found, 'expected a name');
      return name;
    }
    if (line.word(name) == '_') {
      return _form(found, 'wildcard', line, at, name + 1);
    }
    if (found != null) {
      found.add(line.named(name, name));
    }
    return _form(found, 'variable', line, at, name + 1);
  }

  /// A constant pattern from [at] of [line] to [to].
  static int _constant(List<ARange>? found, _Line line, int at, int to) =>
      _form(found, 'constant', line, at, to);

  /// The parentheses at [at] of [line]: a record of the fields they hold,
  /// or the pattern they hold alone.
  int _record(_Line line, int at, List<ARange>? found, _Binding binding) {
    if (found != null && _fields(_inside(line, at), found, binding)) {
      _form(found, 'record', line, at, at + 1);
    }
    return at + 1;
  }

  /// The fields of a record or an object over [line], each a pattern,
  /// perhaps after a name and `:`, or after a `:` alone; and whether they
  /// make a record: none, more than one, or one named.
  bool _fields(_Line line, List<ARange> found, _Binding binding) {
    var record = line[0] == null;
    var next = 0;
    while (line[next] != null) {
      final from = next;
      final named = _Expressions._labeled(line, next)
          ? next + 2
          : line.mark(next, ':')
          ? next + 1
          : null;
      next = _required(line, named ?? next, found, binding, pattern);
      if (named != null) {
        record = true;
        _Expressions._add(found, 'argument', line, from, next);
      }
      if (next == from || !line.mark(next, ',')) {
        expressions._rest(line, next, found);
        break;
      }
      record = true;
      next++;
    }
    return record;
  }

  /// The list from [at] of [line] over the brackets at [brackets]: each
  /// element a pattern or the rest, `...` and perhaps a pattern.
  int _listed(
    _Line line,
    int at,
    int brackets,
    List<ARange>? found,
    _Binding binding,
  ) {
    if (!line.paired(brackets, 'brackets')) {
      statements._problem(found, 'expected [');
      return brackets;
    }
    if (found != null) {
      final inner = _inside(line, brackets);
      var next = 0;
      while (inner[next] != null) {
        final from = next;
        next = inner.mark(next, '...')
            ? _rest(inner, next, found, binding)
            : _required(inner, next, found, binding, pattern);
        if (next == from || !inner.mark(next, ',')) {
          expressions._rest(inner, next, found);
          break;
        }
        next++;
      }
    }
    return _form(found, 'list', line, at, brackets + 1);
  }

  /// The map from [at] of [line] over the braces at [braces]: each entry a
  /// key, `:` and a pattern, or the rest.
  int _mapped(
    _Line line,
    int at,
    int braces,
    List<ARange>? found,
    _Binding binding,
  ) {
    if (found != null) {
      final inner = _inside(line, braces);
      var next = 0;
      while (inner[next] != null) {
        final from = next;
        if (inner.mark(next, '...')) {
          next = _rest(inner, next, found, binding);
        } else {
          next = expressions._required(inner, next, found, cascade: false);
          if (inner.mark(next, ':')) {
            next = _required(inner, next + 1, found, binding, pattern);
          } else {
            statements._problem(found, 'expected :');
          }
          _Expressions._add(found, 'entry', inner, from, next);
        }
        if (next == from || !inner.mark(next, ',')) {
          expressions._rest(inner, next, found);
          break;
        }
        next++;
      }
    }
    return _form(found, 'map', line, at, braces + 1);
  }

  /// The rest of a list or map at [at] of [line]: `...` and perhaps a
  /// pattern.
  int _rest(_Line line, int at, List<ARange>? found, _Binding binding) {
    final next = pattern(line, at + 1, found, binding);
    return _form(found, 'rest', line, at, next);
  }

  /// A [_Line] over what the pair at [at] of [line] holds.
  _Line _inside(_Line line, int at) => expressions._inside(line, at);

  /// A `pattern` of [form] over items [from] to [to] of [line], added to
  /// [found] where it spans more than one token: more than one item, or a
  /// pair other than a string, which is one token to the analyzer; and
  /// [to].
  static int _form(
    List<ARange>? found,
    String form,
    _Line line,
    int from,
    int to,
  ) {
    if (to - from > 1 ||
        form == 'list' ||
        line[from]!.pair && line[from]!.name != 'string') {
      _Expressions._add(found, 'pattern', line, from, to, {
        'form': literal(form),
      });
    }
    return to;
  }
}
