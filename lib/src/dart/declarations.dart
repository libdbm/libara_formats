part of 'dart.dart';

/// The kinds of pair, which every other range of layer 3 is not.
const _pairs = {'parens', 'brackets', 'braces', 'string', 'interpolation'};

/// The kinds of declaration whose braces hold declarations of their own.
const _holders = {'class', 'mixin', 'extension', 'enum'};

/// The kinds of range of layer 3 that are parts of a declaration rather
/// than declarations: its names, an enum's values, what its header holds,
/// and what a body holds.
const _parts = {
  'name', 'value', 'annotation', 'type', 'generic', 'parameter', //
  'initializer', 'block', 'statement', 'if', 'for', 'while', 'do',
  'switch', 'case', 'try', 'catch', 'finally', 'return', 'break',
  'continue', 'yield', 'assert', 'label', 'assignment', 'conditional',
  'binary', 'prefix', 'postfix', 'is', 'as', 'throw', 'call', 'argument',
  'index', 'property', 'cascade', 'section', 'closure', 'instantiation',
  'list', 'set', 'map', 'record', 'entry', 'spread', 'aware', 'strings',
  'symbol', 'pattern',
};

/// The kinds of declaration that may have a body of statements.
const _functions = {'function', 'method', 'constructor', 'getter', 'setter'};

/// The words Dart reserves, which name nothing.
const _reserved = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

/// The words Dart builds in that, though they may be names, stand before a
/// declaration's name rather than as it: `Function` names a type, and the
/// rest are modifiers.
const _unnaming = {
  'Function', 'static', 'external', 'abstract', 'covariant', 'late', //
  'required', 'factory', 'augment',
};

/// The words that start a directive.
const _directives = {'import', 'export', 'part', 'library'};

/// The words that may stand before `class`, `mixin`, `enum` or
/// `extension`.
const _classing = {
  'abstract', 'base', 'final', 'interface', 'sealed', 'augment', 'mixin', //
};

/// The words that may stand before a member's type or name.
const _modifying = {
  'external', 'static', 'abstract', 'covariant', 'late', 'final', 'const', //
  'var', 'factory', 'augment',
};

/// The marks an operator may be declared as.
const _operators = {
  '==', '<', '>', '<=', '>=', '-', '+', '/', '~/', '*', '%', '|', '^', '&', //
  '<<', '>>', '>>>', '[]=', '[]', '~',
};

/// The marks that open a pair, other than an opening quote.
const _openers = {'(', '[', '{', r'${'};

/// Whether [range], of layer 3, is a pair rather than a declaration.
bool _paired(ARange range) => _pairs.contains('${range.get('')}');

/// Whether [range], of layer 3, is a declaration.
bool _declared(ARange range) {
  final kind = '${range.get('')}';
  return !_pairs.contains(kind) && !_parts.contains(kind);
}

/// What a declaration reads as: where it starts and ends among the tokens,
/// its ranges, itself first, its kind, the braces of its body, and, for a
/// function whose body is `=>` and what it returns, the tokens of that.
typedef _Declared = ({
  int start,
  int end,
  String kind,
  List<ARange> ranges,
  ARange? body,
  Range? arrow,
});

/// Where the body of a function ends among a declaration's items, and its
/// braces, or the tokens of what it returns after `=>`.
typedef _Body = ({int end, ARange? braces, Range? arrow});

/// One token or pair of a level, as a declaration is read from them: the
/// index of its first token and of the token after it.
typedef _Item = ({int at, int end, ARange range, String name, bool pair});

/// Reads the declarations of one level of tokens: the top level, or the
/// body of a class, mixin, extension or enum, where each declaration is a
/// member. A pair counts as one item, so what a declaration's brackets hold
/// is passed over whole.
///
/// A declaration runs from its first token that is not whitespace or a
/// comment, metadata included, to its `;` or the braces of its body. Its
/// names are ranges of their own, each a `name` saying the name, so typing
/// in one changes no other range. A member is a constructor by its syntax
/// alone: written with `factory`, as `const X(...)`, or with no return type
/// before `X(...)` or `X.y(...)`.
final class _Declarations {
  _Declarations(this.token, this.pair, this.text);

  /// The token of layer 2 at an index, or null past the last.
  final ARange? Function(int index) token;

  /// The pair starting with the token at an index, if any.
  final ARange? Function(int index) pair;

  /// The text a token covers.
  final String Function(Range token) text;

  /// The diagnostics found while reading, of what does not read as a
  /// declaration or a statement should.
  final problems = <ARange>[];

  /// Reads the statements of bodies, and the expressions in them and in
  /// declarations.
  late final statements = _Statements(this);

  /// The ranges of the declarations from token [from] up to [to], members
  /// where [members], and those within the bodies of the classes, mixins,
  /// extensions and enums among them. An enum's body starts with its
  /// values where [enumerated].
  ///
  /// A declaration may read items up to [limit], past [to]: what one is,
  /// and where it ends, can turn on the item after it.
  List<ARange> read(
    int from,
    int to, {
    bool members = false,
    bool enumerated = false,
    int? limit,
  }) {
    final found = <ARange>[];
    var at = enumerated ? _values(from, to, found) : from;
    while (true) {
      final declared = next(
        at,
        to,
        members: members || enumerated,
        limit: limit,
        detailed: true,
      );
      if (declared == null) {
        return found;
      }
      found.addAll(declared.ranges);
      if (declared.body case final body?
          when _holders.contains(declared.kind)) {
        found.addAll(
          read(
            body.start + 1,
            _inner(body),
            members: true,
            enumerated: declared.kind == 'enum',
          ),
        );
      } else if (_functions.contains(declared.kind)) {
        if (declared.body case final body?) {
          statements.block(body, found);
        }
        if (declared.arrow case final arrow?) {
          final mark = statements._pending.length;
          statements.arrowed(arrow, found);
          statements.said(mark, declared.start, declared.end);
        }
      }
      at = declared.end;
    }
  }

  /// Where what [pair] holds ends: before its closing mark, or at its end
  /// where nothing closes it.
  int _inner(ARange pair) {
    final last = token(pair.end - 1);
    final closing = switch ('${pair.get('')}') {
      'parens' => ')',
      'brackets' => ']',
      _ => '}',
    };
    return pair.length > 1 && last != null && '${last.get('')}' == closing
        ? pair.end - 1
        : pair.end;
  }

  /// The values of an enum from token [from], each added to [found] with
  /// its name, and where its members start: past the `;` after the last
  /// value, or at [to].
  int _values(int from, int to, List<ARange> found) {
    var at = from;
    while (true) {
      final line = _Line(this, at, to);
      if (line[0] == null) {
        return to;
      }
      if (line.mark(0, ';')) {
        return line[0]!.end;
      }
      var at0 = line.metadata(0);
      if (!line.naming(at0) && !line.called(at0)) {
        return at;
      }
      final expressions = statements.expressions;
      final mark = statements._pending.length;
      expressions.annotations(line, 0, found);
      final name = at0;
      at0++;
      final closed = line.angled(at0);
      if (closed > at0) {
        expressions._typed(line, at0, closed, found);
        at0 = closed;
      }
      if (line.mark(at0, '.') && line.naming(at0 + 1)) {
        at0 += 2;
      }
      if (line.paired(at0, 'parens')) {
        expressions._arguments(line, at0, found);
        at0++;
      }
      final end = line[at0 - 1]!.end;
      statements.said(mark, line[0]!.at, end);
      found
        ..add(ranged(line[0]!.at, end - line[0]!.at, {'': literal('value')}))
        ..add(line.named(name, name));
      if (line.mark(at0, ',')) {
        at = line[at0]!.end;
        continue;
      }
      if (line.mark(at0, ';')) {
        return line[at0]!.end;
      }
      return end;
    }
  }

  /// The declaration whose first token is the first at or after [at] that
  /// is not whitespace or a comment, read no further than [to], a member
  /// where [members], or null where there is none. Where [detailed], its
  /// ranges take in what it is made of short of its body: its annotations,
  /// types, type parameters, parameters, initializers and the expressions
  /// its variables are set to.
  _Declared? next(
    int at,
    int to, {
    required bool members,
    int? limit,
    bool detailed = false,
  }) {
    final line = _Line(this, at, limit ?? to);
    if (line[0] == null || line[0]!.at >= to) {
      return null;
    }
    final start = line[0]!.at;
    final names = <ARange>[];
    final details = detailed ? <ARange>[] : null;
    final expressions = statements.expressions;
    final mark = statements._pending.length;
    _Declared made(String kind, int end, [ARange? body, Range? arrow]) {
      final over = line.end(end);
      if (detailed) {
        statements.said(mark, start, over);
      }
      return (
        start: start,
        end: over,
        kind: kind,
        ranges: [
          ranged(start, over - start, {'': literal(kind)}),
          ...names,
          ...?details,
        ],
        body: body,
        arrow: arrow,
      );
    }

    _Declared bodied(String kind, _Body body) =>
        made(kind, body.end, body.braces, body.arrow);

    final head = expressions.annotations(line, 0, details);
    if (!members && _directives.contains(line.word(head))) {
      return made('directive', line.through(head, ';'));
    }
    var classing = head;
    while (_classing.contains(line.word(classing)) &&
        !(line.word(classing) == 'mixin' &&
            line.word(classing + 1) != 'class' &&
            !_classing.contains(line.word(classing + 1)))) {
      classing++;
    }
    final keyword = line.word(classing);
    if (!members &&
        const {'class', 'mixin', 'enum', 'extension'}.contains(keyword)) {
      var named = classing + 1;
      if (keyword == 'extension') {
        if (line.word(named) == 'type') {
          named++;
          if (line.word(named) == 'const') {
            named++;
          }
        } else if (line.word(named) == 'on') {
          named = -1;
        }
      }
      if (named >= 0 && line.naming(named)) {
        names.add(line.named(named, named));
      }
      if (details != null) {
        _header(
          line,
          named >= 0 && line.naming(named) ? named + 1 : classing + 1,
          details,
        );
      }
      for (var at1 = classing + 1; line[at1] != null; at1++) {
        if (line.paired(at1, 'braces')) {
          return made(keyword!, at1 + 1, line[at1]!.range);
        }
        if (line.mark(at1, ';')) {
          return made(keyword!, at1 + 1);
        }
      }
      return made(keyword!, line.length);
    }
    if (!members && keyword == 'typedef') {
      var named = classing + 1;
      // `typedef F<T> = ...;` names first; the older `typedef R F(...);`
      // names after the return type.
      final aliased = line.mark(line.angled(named + 1), '=');
      if (!aliased) {
        final after = line.typed(named);
        if (after > named && line.naming(after)) {
          expressions.type(line, named, details);
          named = after;
        }
      }
      if (line.naming(named)) {
        names.add(line.named(named, named));
        if (details != null) {
          final closed = line.angled(named + 1);
          expressions.generics(line, named + 1, closed, details);
          if (aliased) {
            expressions.type(line, closed + 1, details);
          } else if (line.paired(closed, 'parens')) {
            expressions.parameters(line[closed]!.range, details);
          }
        }
      }
      return made('typedef', line.through(named, ';'));
    }
    var at1 = head;
    var factory = false;
    var constant = false;
    while (_modifying.contains(line.word(at1))) {
      factory = factory || line.word(at1) == 'factory';
      constant = constant || line.word(at1) == 'const';
      at1++;
    }
    // A constructor declared by `new`, or by `factory` with no name
    // before its parameters, says only its own name, if it has one.
    if (members &&
        (line.word(at1) == 'new' || factory && line.paired(at1, 'parens'))) {
      final named = line.word(at1) == 'new' ? at1 + 1 : at1;
      if (line.naming(named)) {
        names.add(line.named(named, named));
      }
      final parens = line.naming(named) ? named + 1 : named;
      if (line.paired(parens, 'parens')) {
        if (details != null) {
          expressions.parameters(line[parens]!.range, details);
        }
        return bodied(
          'constructor',
          _body(line, parens + 1, details, constructor: true),
        );
      }
    }
    var typed = false;
    if (!_accessing(line, at1)) {
      final after = line.typed(at1);
      if (after > at1 &&
          (line.naming(after) ||
              line.called(after) ||
              _accessing(line, after))) {
        typed = true;
        expressions.type(line, at1, details);
        at1 = after;
      }
    }
    String function() => members ? 'method' : 'function';
    switch (line.word(at1)) {
      case 'get' when line.naming(at1 + 1):
        names.add(line.named(at1 + 1, at1 + 1));
        return bodied('getter', _body(line, at1 + 2, details));
      case 'set' when line.naming(at1 + 1):
        names.add(line.named(at1 + 1, at1 + 1));
        _parameters(line, at1 + 2, details);
        return bodied('setter', _body(line, line.after(at1 + 2), details));
      case 'operator' when _operators.contains(line[at1 + 1]?.name):
        names.add(line.named(at1, at1 + 1));
        _parameters(line, at1 + 2, details);
        return bodied(function(), _body(line, line.after(at1 + 2), details));
    }
    if (!line.naming(at1) && !line.called(at1)) {
      return made('declaration', line.fallback(at1));
    }
    final name = at1;
    var last = at1;
    at1++;
    var qualified = false;
    if (line.mark(at1, '.') && line.naming(at1 + 1)) {
      qualified = true;
      last = at1 + 1;
      at1 += 2;
    }
    final closed = line.angled(at1);
    if (closed > at1 && details != null) {
      expressions.generics(line, at1, closed, details);
    }
    at1 = closed;
    if (line.paired(at1, 'parens')) {
      names.add(line.named(name, last));
      final constructor =
          members &&
          (factory || qualified || constant || !typed && line.capital(name));
      _parameters(line, at1, details);
      return bodied(
        constructor ? 'constructor' : function(),
        _body(line, at1 + 1, details, constructor: constructor),
      );
    }
    if (!qualified &&
        (line.mark(at1, '=') || line.mark(at1, ',') || line.mark(at1, ';'))) {
      names.add(line.named(name, name));
      var at2 = at1;
      while (line[at2] != null) {
        if (line.mark(at2, '=')) {
          final from = at2 + 1;
          at2 = line.skipped(from);
          if (details != null) {
            expressions.whole(_within(line, from, at2), details);
          }
        }
        if (line.mark(at2, ',') && line.naming(at2 + 1)) {
          names.add(line.named(at2 + 1, at2 + 1));
          at2 += 2;
          continue;
        }
        if (line.mark(at2, ';')) {
          at2++;
        }
        break;
      }
      return made(members ? 'field' : 'variable', at2);
    }
    return made('declaration', line.fallback(at1));
  }

  /// Whether the word at [at] of [line] starts a getter, a setter or an
  /// operator rather than naming one.
  static bool _accessing(_Line line, int at) => switch (line.word(at)) {
    'get' || 'set' => line.naming(at + 1),
    'operator' => _operators.contains(line[at + 1]?.name),
    _ => false,
  };

  /// The parameters at [at] of [line], where [details] are read and
  /// parentheses stand there.
  void _parameters(_Line line, int at, List<ARange>? details) {
    if (details != null && line.paired(at, 'parens')) {
      statements.expressions.parameters(line[at]!.range, details);
    }
  }

  /// A [_Line] over the items [from] to [to] of [line].
  _Line _within(_Line line, int from, int to) =>
      _Line(this, line[from]?.at ?? line.end(from), line.end(to));

  /// What the header of a class, mixin, enum or extension declares from
  /// [at] of [line], up to its body: its type parameters, the types after
  /// `extends`, `with`, `implements`, `on` and `=`, and the parameters of
  /// an extension type's representation.
  void _header(_Line line, int at, List<ARange> found) {
    final expressions = statements.expressions;
    var next = at;
    while (line[next] != null &&
        !line.paired(next, 'braces') &&
        !line.mark(next, ';')) {
      if (line.mark(next, '<')) {
        final closed = line.angled(next);
        if (closed > next) {
          expressions.generics(line, next, closed, found);
          next = closed;
          continue;
        }
      }
      if (line.paired(next, 'parens')) {
        expressions.parameters(line[next]!.range, found);
      } else if (const {
            'extends', 'with', 'implements', 'on', //
          }.contains(line.word(next)) ||
          line.mark(next, '=') ||
          line.mark(next, ',')) {
        final after = expressions.type(line, next + 1, found);
        if (after > next + 1) {
          next = after;
          continue;
        }
      }
      next++;
    }
  }

  /// The initializers of a constructor over [line], `,` apart: each
  /// assigning a field, calling `super` or `this`, or asserting.
  void _initializers(_Line line, List<ARange> found) {
    final expressions = statements.expressions;
    var next = 0;
    while (line[next] != null) {
      var at = next;
      if (const {'assert', 'super', 'this'}.contains(line.word(at))) {
        at++;
        if (line.mark(at, '.') && _Expressions._worded(line, at + 1)) {
          at += 2;
        }
      } else if (line.naming(at)) {
        at++;
      }
      if (line.paired(at, 'parens')) {
        expressions._arguments(line, at, found);
        at++;
      } else if (line.mark(at, '=')) {
        at = expressions._required(line, at + 1, found);
      } else {
        statements._problem(found, 'expected =');
      }
      _Expressions._add(found, 'initializer', line, next, at);
      if (!line.mark(at, ',')) {
        expressions._rest(line, at, found);
        return;
      }
      next = at + 1;
    }
  }

  /// The body of a function, method, constructor, getter or setter that
  /// starts at [at] of [line]: its braces, its `;`, or an `=>` and what it
  /// returns, and, for a [constructor], its initializers before its braces
  /// or what it redirects to.
  _Body _body(
    _Line line,
    int at,
    List<ARange>? details, {
    bool constructor = false,
  }) {
    _Body braced(int at) => (end: at + 1, braces: line[at]!.range, arrow: null);
    _Body ended(int end) => (end: end, braces: null, arrow: null);
    var at0 = at;
    while (const {'async', 'sync'}.contains(line.word(at0)) ||
        line.mark(at0, '*')) {
      at0++;
    }
    if (constructor && line.mark(at0, ':')) {
      final colon = at0;
      void initialized(int end) {
        if (details != null) {
          _initializers(_within(line, colon + 1, end), details);
        }
      }

      // An initializer may hold braces of its own, as a map; braces after
      // what ends an expression are the body.
      for (at0++; line[at0] != null; at0++) {
        if (line.mark(at0, ';')) {
          initialized(at0);
          return ended(at0 + 1);
        }
        // Braces after `switch (...)` are the switch's own.
        if (line.paired(at0, 'braces') &&
            line.ending(at0 - 1) &&
            !(line.paired(at0 - 1, 'parens') &&
                line.word(at0 - 2) == 'switch')) {
          initialized(at0);
          return braced(at0);
        }
      }
      initialized(at0);
      return ended(at0);
    }
    if (constructor && line.mark(at0, '=')) {
      statements.expressions.constructor(line, at0 + 1, details);
      return ended(line.through(at0, ';'));
    }
    if (line.paired(at0, 'braces')) {
      return braced(at0);
    }
    if (line.mark(at0, '=>')) {
      final end = line.through(at0, ';');
      final last = line.mark(end - 1, ';') ? end - 1 : end;
      if (last <= at0 + 1) {
        return ended(end);
      }
      final from = line[at0 + 1]!.at;
      return (end: end, braces: null, arrow: span(from, line.end(last) - from));
    }
    if (line.mark(at0, ';')) {
      return ended(at0 + 1);
    }
    return ended(line.fallback(at0));
  }
}

/// The items of one declaration, fetched as they are asked for, from the
/// first token at or after a start that is not whitespace or a comment, to
/// no further than a limit.
final class _Line {
  _Line(this.reader, this._next, this.limit);

  final _Declarations reader;
  final int limit;
  final _items = <_Item>[];
  int _next;

  /// The number of items there are.
  int get length {
    while (this[_items.length] != null) {}
    return _items.length;
  }

  /// The item at [index], or null past the last.
  _Item? operator [](int index) {
    while (_items.length <= index) {
      final token = _following();
      if (token == null) {
        return null;
      }
      final name = '${token.get('')}';
      final opened = _openers.contains(name) || _quotes.contains(name)
          ? reader.pair(_next)
          : null;
      if (opened != null) {
        _items.add((
          at: _next,
          end: opened.end,
          range: opened,
          name: '${opened.get('')}',
          pair: true,
        ));
        _next = opened.end;
      } else {
        _items.add((
          at: _next,
          end: _next + 1,
          range: token,
          name: name,
          pair: false,
        ));
        _next++;
      }
    }
    return index < 0 ? null : _items[index];
  }

  /// The next token that is not whitespace or a comment, before the limit.
  ARange? _following() {
    while (_next < limit) {
      final token = reader.token(_next);
      if (token == null) {
        return null;
      }
      if (!_quiet(token)) {
        return token;
      }
      _next++;
    }
    return null;
  }

  /// The token index after item [index], or after the last item where it
  /// is past them.
  int end(int index) {
    final item = this[index - 1];
    return item == null ? (_items.isEmpty ? _next : _items.last.end) : item.end;
  }

  /// The word the item at [index] is, if it is a token.
  String? word(int index) {
    final item = this[index];
    return item == null || item.pair ? null : reader.text(item.range);
  }

  /// Whether the item at [index] is the mark [mark].
  bool mark(int index, String mark) {
    final item = this[index];
    return item != null && !item.pair && item.name == mark;
  }

  /// Whether the item at [index] is a pair of [kind].
  bool paired(int index, String kind) {
    final item = this[index];
    return item != null && item.pair && item.name == kind;
  }

  /// Whether the item at [index] may be a name.
  bool naming(int index) {
    final item = this[index];
    if (item == null || item.pair) {
      return false;
    }
    if (item.name == '#name') {
      return true;
    }
    if (item.name != '#keyword') {
      return false;
    }
    final word = reader.text(item.range);
    return !_reserved.contains(word) && !_unnaming.contains(word);
  }

  /// Whether the item at [index] is a word Dart builds in but does not
  /// reserve, such as `static`, standing as a name: before what follows a
  /// name in a declaration, or a value of an enum.
  bool called(int index) {
    final item = this[index];
    if (item == null ||
        item.pair ||
        item.name != '#keyword' ||
        _reserved.contains(reader.text(item.range))) {
      return false;
    }
    return mark(index + 1, '=') ||
        mark(index + 1, ';') ||
        mark(index + 1, ',') ||
        mark(index + 1, '}') ||
        this[index + 1] == null ||
        paired(index + 1, 'parens');
  }

  /// Whether the name at [index] is written as a type's is: its first
  /// letter, after any underscores, a capital.
  bool capital(int index) => _capital(word(index) ?? '');

  /// Whether the item at [index] may end an expression, so that braces
  /// after it start something else.
  bool ending(int index) {
    final item = this[index];
    if (item == null) {
      return false;
    }
    if (item.pair) {
      return true;
    }
    return switch (item.name) {
      '#name' || '#number' || ')' || ']' || '}' => true,
      '#keyword' => const {
        'this', 'super', 'null', 'true', 'false', //
      }.contains(reader.text(item.range)),
      _ => false,
    };
  }

  /// A `name` range over the items from [from] through [to].
  ARange named(int from, int to) {
    final start = this[from]!.at;
    final end = this[to]!.end;
    return ranged(start, end - start, {
      '': literal('name'),
      'name': literal(
        _joined([
          for (var at = start; at < end; at++) ?reader.token(at),
        ], reader.text),
      ),
    });
  }

  /// The item after metadata from [index]: each annotation.
  int metadata(int index) {
    var at = index;
    while (mark(at, '@')) {
      at = annotation(at);
    }
    return at;
  }

  /// The item after the annotation whose `@` is at [index]: a name,
  /// perhaps qualified, type arguments and arguments.
  int annotation(int index) {
    var at = index + 1;
    if (naming(at) || this[at]?.name == '#keyword') {
      at++;
    }
    while (mark(at, '.') && this[at + 1] != null) {
      at += 2;
    }
    at = angled(at);
    // Arguments follow the name with nothing between, as a record type
    // after the metadata does not.
    if (paired(at, 'parens') && this[at]!.at == this[at - 1]!.end) {
      at++;
    }
    return at;
  }

  /// The item after the type arguments or parameters starting at [index],
  /// or [index] where none start there.
  int angled(int index) {
    if (!mark(index, '<')) {
      return index;
    }
    var depth = 0;
    // Type arguments hold no `;` and no braces, so the search ends at one:
    // what a declaration is depends on nothing past its end.
    for (var at = index; this[at] != null; at++) {
      if (mark(at, ';') || paired(at, 'braces')) {
        return index;
      }
      depth += switch (this[at]!.name) {
        '<' => 1,
        '>' => -1,
        '>>' => -2,
        '>>>' => -3,
        _ => 0,
      };
      if (depth <= 0) {
        return at + 1;
      }
    }
    return index;
  }

  /// The item after the type starting at [index], or [index] where no
  /// type starts there.
  int typed(int index) {
    var at = index;
    if (word(at) == 'void' || word(at) == 'dynamic') {
      at++;
    } else if (paired(at, 'parens')) {
      at++;
    } else if (naming(at) || word(at) == 'Function') {
      if (word(at) != 'Function' ||
          !(mark(at + 1, '<') || paired(at + 1, 'parens'))) {
        at++;
        while (mark(at, '.') && naming(at + 1)) {
          at += 2;
        }
        at = angled(at);
      }
    } else {
      return index;
    }
    if (mark(at, '?')) {
      at++;
    }
    while (word(at) == 'Function') {
      at = angled(at + 1);
      if (!paired(at, 'parens')) {
        return at;
      }
      at++;
      if (mark(at, '?')) {
        at++;
      }
    }
    return at;
  }

  /// The item after the parameters at [index], or [index] where none are.
  int after(int index) => paired(index, 'parens') ? index + 1 : index;

  /// The item after the first [mark] from [index], or after the last item.
  int through(int index, String mark) {
    for (var at = index; this[at] != null; at++) {
      if (this.mark(at, mark)) {
        return at + 1;
      }
    }
    return length;
  }

  /// The item at which an expression from [index] ends: a `,` or `;` that
  /// stands outside its type arguments, or the end.
  int skipped(int index) {
    var depth = 0;
    for (var at = index; this[at] != null; at++) {
      final name = this[at]!.name;
      if (this[at]!.pair) {
        continue;
      }
      if (name == ';' || name == ',' && depth == 0) {
        return at;
      }
      depth = max(
        0,
        depth +
            switch (name) {
              '<' => 1,
              '>' => -1,
              '>>' => -2,
              _ => 0,
            },
      );
    }
    return length;
  }

  /// The item after a declaration that does not read as one, from
  /// [index]: past its `;` or its braces.
  int fallback(int index) {
    for (var at = index; this[at] != null; at++) {
      if (mark(at, ';') || paired(at, 'braces')) {
        return at + 1;
      }
    }
    return length;
  }
}

/// The name [tokens] represent, whitespace and comments left out: an operator
/// as `operator` and the mark, a named constructor as its parts together.
String _joined(List<ARange> tokens, String Function(Range token) text) {
  final parts = [
    for (final token in tokens)
      if (!_quiet(token)) text(token),
  ];
  return parts.length > 1 && parts.first == 'operator'
      ? 'operator ${parts.skip(1).join()}'
      : parts.join();
}

/// Whether [token] is whitespace or a comment.
bool _quiet(ARange token) {
  final name = '${token.get('')}';
  return name == '#space' || name == '#comment';
}

/// Every range of layer 3 that holds the token at [index]: those that
/// cross either of its edges, and those over it alone.
List<ARange> _containing(Layered<int> document, int index) {
  final found = <ARange>{
    for (final (_, range) in document.crossing(3, index)) range,
    for (final (_, range) in document.crossing(3, index + 1)) range,
    for (final (_, range) in document.within(3, span(index, 1)))
      if (range.start == index) range,
  };
  return found.toList();
}

/// The innermost pair around [region], or null where none is.
ARange? _around(Layered<int> document, Range region) {
  ARange? inner;
  for (final (_, range) in document.crossing(3, region.start)) {
    if (_paired(range) &&
        region.end <= range.end &&
        (inner == null || range.length < inner.length)) {
      inner = range;
    }
  }
  return inner;
}

/// The declaration whose body [level], a pair, is, where it is the body
/// of a class, mixin, extension or enum, or null.
ARange? _holder(Layered<int> document, ARange? level) {
  if (level == null || '${level.get('')}' != 'braces') {
    return null;
  }
  return _held(document, level);
}

/// The class, mixin, extension or enum whose body is the braces over
/// [body], if any: one that ends where they do, with no pair of its own
/// around them, as a method's body has its class's around it.
ARange? _held(Layered<int> document, Range body) {
  final around = document.crossing(3, body.start);
  for (final (_, range) in around) {
    if (range.end == body.end &&
        _holders.contains('${range.get('')}') &&
        !around.any(
          (pair) =>
              _paired(pair.$2) &&
              pair.$2.start > range.start &&
              pair.$2.end >= body.end,
        )) {
      return range;
    }
  }
  return null;
}

/// The tokens of layer 2 from an index on, fetched a stretch at a time.
final class _Tokens {
  _Tokens(this.document);

  final Layered<int> document;
  final _cache = <int, ARange?>{};

  ARange? call(int index) {
    if (_cache.containsKey(index)) {
      return _cache[index];
    }
    final fetched = document.span(2, span(index, 64));
    for (var at = 0; at < 64; at++) {
      _cache[index + at] = at < fetched.length ? fetched[at].$2 : null;
    }
    return _cache[index];
  }
}

/// The pair of [document] that starts with the token at [index], if any.
ARange? _opening(Layered<int> document, int index) {
  for (final range in _containing(document, index)) {
    if (range.start == index && _paired(range)) {
      return range;
    }
  }
  return null;
}
