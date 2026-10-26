part of 'roff.dart';

/// The one reading of a roff source, line by line: the notations it marks,
/// each named for the element it represents, and the elements, in UTF-16 units
/// of the source.
///
/// Ported from markwrite's `roff.dart`, which marked a pair of tokens for
/// each element; here an element is a range from its first token to its
/// last, and one no request opens, an implied paragraph, has none.
final class _Scan {
  _Scan(this.source, this.macros, this.limits);

  final String source;
  final Map<String, _Macro> macros;
  final Limits limits;

  /// The notations, as they are marked.
  final List<Found> marks = [];

  /// The elements, as they close.
  final List<Found> elements = [];

  /// Where the reading stopped at a cap, and why.
  (int, String)? stop;

  /// The blocks standing open, outermost first, and whether each runs on
  /// only until the next block request, as a paragraph does, or until its
  /// partner closes it, as a container does; and whether nothing represents
  /// it, as a paragraph no request opened.
  final List<
    ({
      String name,
      bool running,
      int start,
      Map<String, String> said,
      bool marks,
    })
  >
  blocks = [];

  /// The rank of the last heading, which a step in a heading counts from.
  int depth = 0;

  /// The faces standing open, from an escape or a font request, outermost
  /// first, each with where it opened.
  final List<(String, int)> fonts = [];

  /// Where the content of the open block ended, which is where it closes.
  int? content;

  /// The next text line is the tag of a tagged paragraph.
  bool tagging = false;

  /// The next text line begins the paragraph under a tag.
  bool hanging = false;

  /// The line being read is the tag, which closes at the line's end.
  bool tagged = false;

  /// A block opened by a request with no arguments, whose content is the
  /// next line, and which closes at that line's end.
  String? lined;

  /// What eqn's delim said: the characters that open and close a formula
  /// in running text, or nothing.
  String? opens;
  String? closes;

  /// Whether a delim line was read, which sets what every line after it
  /// reads.
  bool delimited = false;

  /// The strings defined, by name, each as the words it shows: those
  /// defined before the source, then those it defines.
  Map<String, String> strings = {};

  /// Whether the source defines a string, which sets what every line after
  /// it that uses one reads.
  bool defined = false;

  /// The spaces and tabs between a request's arguments.
  static final _spaces = RegExp(r'[ \t]+');

  /// Told where each line starts before it is read, where it is set.
  void Function(int at)? line;

  /// Reads the source.
  void read() {
    var at = 0;
    while (at < source.length && stop == null) {
      line?.call(at);
      final end = _lineEnd(at);
      final next = end < source.length ? end + 1 : end;
      final unit = source.codeUnitAt(at);
      if (unit == 0x2E || unit == 0x27) {
        at = _request(at, end, next);
      } else {
        _text(at, end);
        at = next;
      }
    }
    contained = blocks.any((block) => !block.running);
    _closeAll(content ?? (stop?.$1 ?? source.length));
  }

  /// Whether a container, which only its partner closes, stood open at the
  /// end of the source, before the reading closed it.
  bool contained = false;

  int _lineEnd(int from) {
    final held = source.indexOf('\n', from);
    return held < 0 ? source.length : held;
  }

  /// Markup of [length] from [start], called [name], saying [said].
  void _mark(
    int start,
    int length,
    String name, [
    Map<String, String> said = const {},
  ]) {
    if (length > 0) {
      marks.add((start, start + length, name, said));
    }
  }

  /// Markup that is syntax: an escape showing [said], or, called
  /// [name], a request that shows nothing.
  void _syntax(int start, int length, [String said = '', String? name]) {
    _mark(
      start,
      length,
      name ?? '#escape',
      name == null ? {'shows': said} : const {},
    );
  }

  // Blocks.

  void _openBlock(
    String name,
    int start,
    int length, {
    Map<String, String> said = const {},
    bool running = true,
    bool marks = false,
  }) {
    final deepest = limits.depth;
    if (deepest != null && blocks.length >= deepest) {
      stop ??= (start, 'blocks nested deeper than $deepest');
      return;
    }
    if (!marks) {
      _mark(start, length, name, said);
    }
    blocks.add((
      name: name,
      running: running,
      start: start,
      said: said,
      marks: marks,
    ));
    content = null;
  }

  /// Closes the innermost block at [at], with markup of [length]
  /// there, and the faces still open in it.
  void _closeBlock(int at, [int length = 0]) {
    final held = blocks.removeLast();
    _closeFonts(at);
    _mark(at, length, held.name);
    elements.add((
      held.start,
      at + length,
      held.name,
      held.marks ? {...held.said, 'implied': ''} : held.said,
    ));
    content = null;
  }

  /// Ends every paragraph standing open, as a block request does.
  void _closeParagraphs(int at) {
    while (blocks.isNotEmpty && blocks.last.running) {
      _closeBlock(content ?? at);
    }
    tagging = false;
    hanging = false;
  }

  void _closeAll(int at) {
    while (blocks.isNotEmpty) {
      _closeBlock(content ?? at);
    }
    _closeFonts(at);
    tagging = false;
    hanging = false;
    lined = null;
  }

  bool get _verbatim {
    for (var at = blocks.length - 1; at >= 0; at -= 1) {
      if (blocks[at].running) {
        return false;
      }
      if (blocks[at].name == 'pre' || blocks[at].name == 'equation') {
        return true;
      }
    }
    return false;
  }

  /// Sees that a paragraph stands open for text at [at], opening one where
  /// none does and the block around it is not verbatim.
  void _paragraph(int at) {
    if (tagging) {
      tagging = false;
      tagged = true;
      _openBlock('dt', at, 0);
      return;
    }
    if (_verbatim) {
      return;
    }
    if (blocks.isNotEmpty && blocks.last.running) {
      return;
    }
    // A paragraph no request opened is marked as implied, so a writer
    // writes none for it; a description hangs under its term regardless.
    if (hanging) {
      _openBlock('dd', at, 0);
    } else {
      // Marked, because roff represents this block at neither end, and saying
      // `implied` besides, which is roff's own word for it and what a
      // conversion of a page carries.
      _openBlock('p', at, 0, marks: true);
    }
    hanging = false;
  }

  /// The end of a line of content at [end]: a tag closes there, and what
  /// follows hangs under it.
  void _lined(int end) {
    if (tagged) {
      tagged = false;
      _closeBlock(end);
      hanging = true;
    } else {
      content = end;
    }
  }

  // Faces.

  void _openFonts(List<String> names, int start, int length) {
    var held = length;
    for (final name in names) {
      _mark(start, held, name);
      fonts.add((name, start));
      held = 0;
    }
  }

  /// Closes every open face at [at]: the innermost with the escape of
  /// [length] standing there, the rest with nothing, after it, so that
  /// each ends where the one inside it does.
  void _closeFonts(int at, [int length = 0]) {
    var here = at;
    var held = length;
    while (fonts.isNotEmpty) {
      final (name, start) = fonts.removeLast();
      _mark(here, held, name);
      here += held;
      elements.add((start, here, name, const {}));
      held = 0;
    }
  }

  /// The faces that stood before the last change of face, which `\fP`
  /// brings back, as roff has it.
  List<String> previous = const [];

  // Lines.

  void _text(int at, int end) {
    if (lined case final name?) {
      lined = null;
      // A request between may have closed the block that waited for its
      // words, and then this line is words of its own.
      if (blocks.isNotEmpty && blocks.last.name == name) {
        _escapes(at, end);
        _closeBlock(end);
        return;
      }
    }
    if (_blank(at, end)) {
      if (_verbatim) {
        content = end;
      } else {
        _closeParagraphs(at);
      }
      return;
    }
    if (blocks.isNotEmpty &&
        blocks.last.name == 'equation' &&
        source.startsWith('delim', at)) {
      _delim(at, end);
      return;
    }
    _paragraph(at);
    _formulae(at, end);
    _lined(end);
  }

  /// eqn's `delim xy`: from here on a formula in running text stands
  /// between the two characters, or between none after `delim off`. The
  /// line is syntax, not part of the equation it stands in.
  void _delim(int at, int end) {
    final held = _arguments(at + 5, end);
    if (held.isEmpty || held.first.$3 == 'off' || held.first.$3.length < 2) {
      opens = null;
      closes = null;
    } else {
      opens = held.first.$3[0];
      closes = held.first.$3[1];
    }
    delimited = true;
    _mark(at, (end < source.length ? end + 1 : end) - at, '#pi', {
      'delim': held.isEmpty ? 'off' : held.first.$3,
    });
  }

  /// A line of words with the formulae eqn's delimiters mark in it, each
  /// an inline element eqn reads, and the escapes in the words between.
  void _formulae(int from, int to) {
    final left = opens;
    final right = closes;
    if (left == null || right == null) {
      _escapes(from, to);
      return;
    }
    var at = from;
    while (at < to) {
      final start = source.indexOf(left, at);
      if (start < 0 || start >= to) {
        break;
      }
      final stop = source.indexOf(right, start + 1);
      if (stop < 0 || stop >= to) {
        break;
      }
      _escapes(at, start);
      _mark(start, 1, 'math');
      _mark(stop, 1, 'math');
      elements.add((start, stop + 1, 'math', const {'notation': 'eqn'}));
      at = stop + 1;
    }
    _escapes(at, to);
  }

  bool _blank(int at, int end) {
    for (var here = at; here < end; here += 1) {
      final unit = source.codeUnitAt(here);
      if (unit != 0x20 && unit != 0x09) {
        return false;
      }
    }
    return true;
  }

  int _request(int at, int end, int next) {
    var here = at + 1;
    while (here < end && _space(source.codeUnitAt(here))) {
      here += 1;
    }
    // A comment is the whole line, and a request with no name is nothing.
    if (source.startsWith(r'\"', here) || source.startsWith('\\#', here)) {
      _syntax(at, next - at, '', '#comment');
      return next;
    }
    final named = here;
    while (here < end && !_space(source.codeUnitAt(here))) {
      here += 1;
    }
    final name = source.substring(named, here);
    while (here < end && _space(source.codeUnitAt(here))) {
      here += 1;
    }
    final arguments = here;
    switch (name) {
      case '':
        _syntax(at, next - at, '', '#pi');
        return next;
      case 'de' || 'de1' || 'am' || 'am1' || 'ig':
        // A definition runs to the line that ends it, and none of it is
        // words a reader sees. That line is `..`, or the request its last
        // argument names: a definition's second, an ignored stretch's first.
        final said = source.substring(arguments, end);
        final comment = said.indexOf(r'\"');
        final words = (comment < 0 ? said : said.substring(0, comment))
            .trim()
            .split(_spaces);
        final close = switch ((name, words.length)) {
          ('ig', >= 1) when words.first.isNotEmpty => words.first,
          (_, >= 2) when name != 'ig' => words[1],
          _ => '.',
        };
        return _through(at, next, (from, to) {
          final line = source.substring(from, to).trimRight();
          if (line.length < 2 || (line[0] != '.' && line[0] != "'")) {
            return false;
          }
          final request = line.substring(1).trimLeft().split(_spaces).first;
          return request == close;
        });
      case 'ds' || 'ds1' || 'as' || 'as1':
        // A string's definition: its name, then the rest of the line, a
        // quote before it kept from the words, as what it shows.
        final said = source.substring(arguments, end);
        final cut = said.indexOf(_spaces);
        final called = cut < 0 ? said : said.substring(0, cut);
        var words = cut < 0 ? '' : said.substring(cut).trimLeft();
        if (words.startsWith('"')) {
          words = words.substring(1);
        }
        final shows = _said(words);
        final value = name.startsWith('as')
            ? '${strings[called] ?? ''}$shows'
            : shows;
        if (called.isNotEmpty) {
          strings = {...strings, called: value};
          defined = true;
        }
        _mark(at, next - at, '#pi', {
          if (called.isNotEmpty) 'string': called,
          if (called.isNotEmpty) 'value': value,
        });
        return next;
      case 'if' || 'ie' || 'el':
        // A condition may hold a braced group over several lines, none of
        // which is read.
        var depth = _braces(at, end);
        if (depth <= 0) {
          _syntax(at, next - at, '', '#pi');
          return next;
        }
        return _through(at, next, (from, to) {
          depth += _braces(from, to);
          return depth <= 0;
        });
    }
    final macro = macros[name];
    switch (macro) {
      case _Table():
        return _table(at, next);
      case null || _Hidden():
        _syntax(at, next - at, '', '#pi');
      case _Lined(name: final held):
        _closeAll(content ?? at);
        if (arguments >= end) {
          _openBlock(held, at, next - at);
          lined = held;
        } else {
          _openBlock(held, at, arguments - at);
          _words(arguments, end, held);
          _closeBlock(end);
        }
      case _Paragraph(name: final held):
        _closeParagraphs(at);
        _openBlock(held, at, next - at);
      case _Headed(:final level, :final inline):
        _closeAll(content ?? at);
        final held = _arguments(arguments, end);
        var from = arguments;
        var rank = level;
        if (rank == null && held.isNotEmpty) {
          rank = _leveled(held.first.$3);
          if (rank != null) {
            from = held.first.$2;
            while (from < end && _space(source.codeUnitAt(from))) {
              from += 1;
            }
          }
        }
        rank ??= 1;
        depth = rank;
        final name = 'h$rank';
        if (!inline) {
          _openBlock(name, at, next - at);
        } else if (from >= end) {
          _openBlock(name, at, next - at);
          lined = name;
        } else {
          _openBlock(name, at, from - at);
          _words(from, end, name);
          _closeBlock(end);
        }
      case _Tagged():
        _closeParagraphs(at);
        _syntax(at, next - at, '', 'dt');
        tagging = true;
      case _Item(:final tag):
        _closeParagraphs(at);
        final held = _arguments(arguments, end);
        final said = held.isNotEmpty ? _said(held.first.$3) : tag;
        _openBlock('li', at, next - at, said: {'tag': ?said});
      case _Ignored(:final until):
        _closeParagraphs(at);
        return _through(at, next, (from, to) => _requested(from, to) == until);
      case _Opening(
        name: final held,
        :final attribute,
        :final prefix,
        :final kind,
        :final said,
      ):
        _closeParagraphs(at);
        final first = _arguments(arguments, end);
        _openBlock(
          held,
          at,
          next - at,
          said: {
            if (attribute != null && first.isNotEmpty)
              attribute: '$prefix${_said(first.first.$3)}',
            'class': ?kind,
            ...said,
          },
          running: false,
        );
      case _Closing(name: final held):
        _closeParagraphs(at);
        if (blocks.isNotEmpty && blocks.last.name == held) {
          _closeBlock(at, next - at);
        } else {
          _syntax(at, next - at, '', '#pi');
        }
      case _Font(:final names):
        if (arguments >= end) {
          _syntax(at, next - at, '', '#pi');
        } else {
          _paragraph(at);
          _openFonts(names, at, arguments - at);
          _escapes(arguments, end);
          _lined(end);
          _closeFonts(end);
        }
      case _Alternating(:final first, :final second):
        if (arguments >= end) {
          _syntax(at, next - at, '', '#pi');
        } else {
          _paragraph(at);
          _syntax(at, arguments - at, '', '#pi');
          var here = arguments;
          for (final (index, (start, stop, _)) in _arguments(
            arguments,
            end,
          ).indexed) {
            if (start > here) {
              _syntax(here, start - here, '', '#pi');
            }
            final name = index.isEven ? first : second;
            // The quotes round an argument are syntax inside it.
            final quoted = source.codeUnitAt(start) == 0x22;
            final closed =
                quoted &&
                stop - start > 1 &&
                source.codeUnitAt(stop - 1) == 0x22;
            if (quoted) {
              _syntax(start, 1, '', name);
            }
            _escapes(start + (quoted ? 1 : 0), stop - (closed ? 1 : 0));
            _closeFonts(stop - (closed ? 1 : 0));
            if (closed) {
              _syntax(stop - 1, 1, '', name);
            }
            elements.add((start, stop, name, const {}));
            here = stop;
          }
          if (end > here) {
            _syntax(here, end - here, '', '#pi');
          }
          _lined(end);
        }
      case _Titled(name: final held, :final attributes):
        _closeAll(content ?? at);
        final said = _arguments(arguments, end);
        final titled = {
          for (final (index, name) in attributes.indexed)
            if (index < said.length) name: _said(said[index].$3),
        };
        _mark(at, end - at, held, titled);
        elements.add((at, end, held, titled));
      case _Breaking(:final name):
        _mark(at, next - at, name);
        elements.add((at, next, name, const {}));
    }
    return next;
  }

  /// The rank a heading's argument says: a number, or a step from the last
  /// heading's rank, held to the six ranks a sheet resolves.
  int? _leveled(String said) {
    if (said.isEmpty) {
      return null;
    }
    final unit = said.codeUnitAt(0);
    final stepped = unit == 0x2B || unit == 0x2D;
    final number = int.tryParse(stepped ? said.substring(1) : said);
    if (number == null) {
      return null;
    }
    final rank = stepped ? depth + (unit == 0x2B ? number : -number) : number;
    return rank.clamp(1, 6);
  }

  /// The words of a heading or a title in the rest of a line: one quoted
  /// argument with its quotes as syntax, else the line as it stands.
  void _words(int from, int to, String name) {
    if (source.codeUnitAt(from) == 0x22 &&
        to - from > 1 &&
        source.codeUnitAt(to - 1) == 0x22) {
      _syntax(from, 1, '', name);
      _escapes(from + 1, to - 1);
      _syntax(to - 1, 1, '', name);
    } else {
      _escapes(from, to);
    }
  }

  // Tables.

  /// A tbl table whose request stands at [at]: its options and format,
  /// each line of which ends with a semicolon or a stop, and any `.T&`,
  /// rule or request among its rows are syntax of the table, and each other
  /// line through `.TE` is a row.
  int _table(int at, int next) {
    _closeParagraphs(at);
    _syntax(at, next - at, '', 'table');
    var tab = '\t';
    var formatted = false;
    var optioned = false;
    var from = next;
    while (from < source.length) {
      final to = _lineEnd(from);
      final after = to < source.length ? to + 1 : to;
      final request = _requested(from, to);
      if (request == 'TE') {
        _syntax(from, after - from, '', 'table');
        elements.add((at, after, 'table', const {}));
        return after;
      }
      if (!formatted) {
        _syntax(from, after - from, '', 'table');
        final line = source.substring(from, to).trimRight();
        if (!optioned && line.endsWith(';')) {
          if (_tabbed.firstMatch(line) case final match?) {
            tab = match[1]!;
          }
        } else if (line.endsWith('.')) {
          formatted = true;
        }
        optioned = true;
        from = after;
        continue;
      }
      if (request == 'T&') {
        _syntax(from, after - from, '', 'table');
        formatted = false;
        from = after;
        continue;
      }
      final line = source.substring(from, to).trim();
      if (request != null || line == '_' || line == '=') {
        _syntax(from, after - from, '', request == null ? 'table' : '#pi');
        from = after;
        continue;
      }
      from = _row(from, tab);
    }
    elements.add((at, source.length, 'table', const {}));
    return source.length;
  }

  /// The character a table's options say divides its cells.
  static final _tabbed = RegExp(r'tab\s*\((.)\)');

  /// The row starting at [from], its cells parted by [tab]: a cell is the
  /// words up to the next, or a text block from `T{` at the end of a line
  /// to `T}` at the start of one. Each cell's faces close with it, as tbl
  /// sets each on its own. Past the row's line end.
  int _row(int from, String tab) {
    var at = from;
    while (true) {
      final end = _lineEnd(at);
      if (source.startsWith('T{', at) && at + 2 == end) {
        final close = _block(at, end);
        if (close < 0) {
          _closeFonts(source.length);
          elements.add((at, source.length, 'td', const {}));
          elements.add((from, source.length, 'tr', const {}));
          return source.length;
        }
        _closeFonts(close);
        _syntax(close, 2, '', 'td');
        elements.add((at, close + 2, 'td', const {}));
        at = close + 2;
      } else {
        final mark = _find(source, tab.codeUnitAt(0), at, end);
        final stop = mark < 0 ? end : mark;
        _escapes(at, stop);
        _closeFonts(stop);
        elements.add((at, stop, 'td', const {}));
        at = stop;
      }
      final line = _lineEnd(at);
      if (at < line && source.startsWith(tab, at)) {
        _syntax(at, tab.length, '', 'tr');
        at += tab.length;
        continue;
      }
      elements.add((from, line, 'tr', const {}));
      return line < source.length ? line + 1 : line;
    }
  }

  /// A text block opening with the `T{` at [at], which ends its line at
  /// [end]: its lines are words, or syntax where they are requests. Where
  /// the `T}` closing it stands, or -1 where none does.
  int _block(int at, int end) {
    _syntax(at, end < source.length ? end + 1 - at : end - at, '', 'td');
    var from = end + 1;
    while (from < source.length) {
      if (source.startsWith('T}', from)) {
        return from;
      }
      final to = _lineEnd(from);
      if (_requested(from, to) != null) {
        _syntax(
          from,
          to < source.length ? to + 1 - from : to - from,
          '',
          '#pi',
        );
      } else {
        _escapes(from, to);
      }
      from = to + 1;
    }
    return -1;
  }

  /// The name of the request on the line from [from] to [to], or null
  /// where the line is words.
  String? _requested(int from, int to) {
    if (from >= to) {
      return null;
    }
    final unit = source.codeUnitAt(from);
    if (unit != 0x2E && unit != 0x27) {
      return null;
    }
    var at = from + 1;
    while (at < to && _space(source.codeUnitAt(at))) {
      at += 1;
    }
    final named = at;
    while (at < to && !_space(source.codeUnitAt(at))) {
      at += 1;
    }
    return source.substring(named, at);
  }

  /// Marks from [at] through the first line for which [ends] holds, or to
  /// the end of the source, as one token showing nothing.
  int _through(int at, int next, bool Function(int from, int to) ends) {
    var from = next;
    while (from < source.length) {
      final to = _lineEnd(from);
      final after = to < source.length ? to + 1 : to;
      if (ends(from, to)) {
        _syntax(at, after - at, '', '#pi');
        return after;
      }
      from = after;
    }
    _syntax(at, source.length - at, '', '#pi');
    return source.length;
  }

  /// How many braced groups the line opens beyond those it closes.
  int _braces(int from, int to) {
    var depth = 0;
    for (var at = from; at + 1 < to; at += 1) {
      if (source.codeUnitAt(at) == 0x5C) {
        final unit = source.codeUnitAt(at + 1);
        if (unit == 0x7B) {
          depth += 1;
        } else if (unit == 0x7D) {
          depth -= 1;
        }
        at += 1;
      }
    }
    return depth;
  }

  static bool _space(int unit) => unit == 0x20 || unit == 0x09;

  /// The arguments of a request between [from] and [to]: where each stands
  /// in the source, quotes and all, and what it says with its quotes off.
  List<(int, int, String)> _arguments(int from, int to) {
    final held = <(int, int, String)>[];
    var at = from;
    while (at < to) {
      while (at < to && _space(source.codeUnitAt(at))) {
        at += 1;
      }
      if (at >= to) {
        break;
      }
      final start = at;
      if (source.codeUnitAt(at) == 0x22) {
        final said = StringBuffer();
        at += 1;
        while (at < to) {
          if (source.codeUnitAt(at) == 0x22) {
            if (at + 1 < to && source.codeUnitAt(at + 1) == 0x22) {
              said.write('"');
              at += 2;
              continue;
            }
            at += 1;
            break;
          }
          said.writeCharCode(source.codeUnitAt(at));
          at += 1;
        }
        held.add((start, at, said.toString()));
      } else {
        while (at < to && !_space(source.codeUnitAt(at))) {
          at += 1;
        }
        held.add((start, at, source.substring(start, at)));
      }
    }
    return held;
  }

  /// What an argument says as plain words: its escapes read, its font
  /// changes dropped.
  String _said(String held) {
    final out = StringBuffer();
    var at = 0;
    while (at < held.length) {
      if (held.codeUnitAt(at) != 0x5C || at + 1 >= held.length) {
        out.writeCharCode(held.codeUnitAt(at));
        at += 1;
        continue;
      }
      final (length, said) = _escape(held, at, held.length, strings);
      out.write(said ?? '');
      at += length;
    }
    return out.toString();
  }

  // Escapes.

  /// Marks every escape between [from] and [to], opening and closing faces
  /// as the font escapes say.
  void _escapes(int from, int to) {
    var at = from;
    while (at < to) {
      if (source.codeUnitAt(at) != 0x5C) {
        at += 1;
        continue;
      }
      if (at + 1 >= to) {
        _syntax(at, to - at);
        return;
      }
      final unit = source.codeUnitAt(at + 1);
      if (unit == 0x22 || unit == 0x23) {
        // A comment runs to the end of the line, and a whole-line one
        // takes the line ending with it.
        final end = _lineEnd(at);
        _syntax(
          at,
          (unit == 0x23 && end < source.length ? end + 1 : end) - at,
          '',
          '#comment',
        );
        return;
      }
      if (unit == 0x66) {
        at += _font(at, to);
        continue;
      }
      final (length, said) = _escape(source, at, to, strings);
      _syntax(at, length, said ?? '');
      at += length;
    }
  }

  /// A font escape at [at]: the faces it opens or closes.
  int _font(int at, int to) {
    final (length, named) = _fontName(at + 2, to);
    final names = _faced(named);
    final whole = 2 + length;
    if (names == null) {
      _syntax(at, whole);
      return whole;
    }
    final restoring = named == 'P' || named == '[]';
    if (names.isEmpty) {
      if (fonts.isEmpty) {
        if (restoring && previous.isNotEmpty) {
          final held = previous;
          previous = const [];
          _openFonts(held, at, whole);
        } else {
          _syntax(at, whole);
        }
        return whole;
      }
      final held = [for (final (name, _) in fonts) name];
      _closeFonts(at, whole);
      if (restoring && previous.isNotEmpty) {
        _openFonts(previous, at + whole, 0);
      }
      previous = held;
      return whole;
    }
    if (fonts.length == names.length &&
        fonts.indexed.every((held) => names[held.$1] == held.$2.$1)) {
      _syntax(at, whole);
      return whole;
    }
    final held = [for (final (name, _) in fonts) name];
    _closeFonts(at);
    _openFonts(names, at, whole);
    previous = held;
    return whole;
  }

  /// The name a font escape carries after `\f`: one letter, two in
  /// parentheses, or any in brackets, and how long its markup is.
  (int, String) _fontName(int at, int to) {
    if (at >= to) {
      return (0, '');
    }
    final unit = source.codeUnitAt(at);
    if (unit == 0x28 && at + 2 <= to) {
      final end = at + 3 <= to ? at + 3 : to;
      return (end - at, source.substring(at + 1, end));
    }
    if (unit == 0x5B) {
      final close = _find(source, 0x5D, at, to + 1);
      if (close < 0) {
        return (1, '');
      }
      return (close + 1 - at, source.substring(at + 1, close));
    }
    return (1, String.fromCharCode(unit));
  }

  /// An escape at [at] in [held]: how long its markup is, and what it
  /// shows, or null for one that shows nothing.
  static (int, String?) _escape(
    String held,
    int at, [
    int? until,
    Map<String, String> strings = const {},
  ]) {
    final to = until ?? held.length;
    if (at + 1 >= to) {
      return (to - at, null);
    }
    final unit = held.codeUnitAt(at + 1);
    switch (unit) {
      case 0x2D: // \-
        return (2, '-');
      case 0x65 || 0x5C: // \e \\
        return (2, r'\');
      case 0x26 || 0x25 || 0x63 || 0x7A || 0x2F || 0x2C: // \& \% \c \z \/ \,
        return (2, null);
      case 0x7E || 0x20 || 0x30: // \~ \space \0
        return (2, ' ');
      case 0x7C || 0x5E: // \| \^
        return (2, null);
      case 0x2E: // \.
        return (2, '.');
      case 0x27: // \'
        return (2, '´');
      case 0x60: // \`
        return (2, '`');
      case 0x74: // \t
        return (2, '\t');
      case 0x28: // \(xx
        final end = at + 4 <= to ? at + 4 : to;
        return (end - at, _glyphs[held.substring(at + 2, end)]);
      case 0x5B: // \[name]
        final close = _find(held, 0x5D, at, to);
        if (close < 0) {
          return (2, null);
        }
        final name = held.substring(at + 2, close);
        if (name.length > 1 && name.codeUnitAt(0) == 0x75) {
          final point = int.tryParse(name.substring(1), radix: 16);
          if (point != null && point <= 0x10FFFF) {
            return (close + 1 - at, String.fromCharCode(point));
          }
        }
        return (close + 1 - at, _glyphs[name]);
      case 0x2A: // \*x, a string, which shows what it was defined as
        final length = _named(held, at + 2, to, false);
        final name = held.substring(at + 2, at + length);
        return (length, strings[_unbracketed(name)]);
      case 0x6E || 0x67 || 0x73: // \nx \gx \sN
        return (_named(held, at + 2, to, unit == 0x73), null);
      case 0x66: // \f, met here only in an argument's words
        final next = at + 2 < to ? held.codeUnitAt(at + 2) : 0;
        return switch (next) {
          0x28 => (5 <= to - at ? 5 : to - at, null),
          0x5B => (_bracketed(held, at + 2, to), null),
          0 => (2, null),
          _ => (3, null),
        };
      case 0x68 ||
          0x76 ||
          0x6C ||
          0x4C ||
          0x77 ||
          0x6F ||
          0x62 ||
          0x44 ||
          0x53 ||
          0x48 ||
          0x41 ||
          0x43 ||
          0x4E ||
          0x52 ||
          0x58 ||
          0x5A ||
          0x59 ||
          0x56 ||
          0x45 ||
          0x4F ||
          0x6B ||
          0x4D ||
          0x6D:
        // \h'..' and its kind: an argument in quotes, or a name, or a
        // letter.
        return (quoted(held, at + 2, to), null);
      default:
        return (2, null);
    }
  }

  /// The markup of a name after an escape at [at]: one letter, two after
  /// a parenthesis, or any in brackets; a size may also be signed digits.
  static int _named(String held, int at, int to, bool sized) {
    final start = at - 2;
    if (at >= to) {
      return at - start;
    }
    final unit = held.codeUnitAt(at);
    if (unit == 0x28) {
      return (at + 3 <= to ? at + 3 : to) - start;
    }
    if (unit == 0x5B) {
      return _bracketed(held, at, to);
    }
    if (sized) {
      var here = at;
      if (unit == 0x2B || unit == 0x2D) {
        here += 1;
      }
      if (here < to && held.codeUnitAt(here) == 0x27) {
        return quoted(held, at, to);
      }
      var digits = 0;
      while (here < to && digits < 2 && _digit(held.codeUnitAt(here))) {
        here += 1;
        digits += 1;
      }
      return here - start;
    }
    return at + 1 - start;
  }

  /// The length of an escape whose markup ends at a closing bracket at
  /// or after [at], measured from two before [at].
  static int _bracketed(String held, int at, int to) {
    final start = at - 2;
    final close = _find(held, 0x5D, at, to);
    return (close < 0 ? at + 1 : close + 1) - start;
  }

  /// The length of an escape at [at] - 2 whose argument, where it has one,
  /// is quoted: through the closing quote, else the one character.
  static int quoted(String held, int at, int to) {
    final start = at - 2;
    if (at < to && held.codeUnitAt(at) == 0x27) {
      final close = _find(held, 0x27, at + 1, to);
      return (close < 0 ? to : close + 1) - start;
    }
    if (at < to && held.codeUnitAt(at) == 0x28) {
      return (at + 3 <= to ? at + 3 : to) - start;
    }
    if (at < to && held.codeUnitAt(at) == 0x5B) {
      return _bracketed(held, at, to);
    }
    return (at < to ? at + 1 : to) - start;
  }

  static bool _digit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// A name as an escape represents it, `x`, `(xx` or `[name]`, without what
  /// represents its length.
  static String _unbracketed(String name) => name.startsWith('(')
      ? name.substring(1)
      : name.startsWith('[') && name.endsWith(']')
      ? name.substring(1, name.length - 1)
      : name;

  /// Where [unit] first stands in [held] from [at] and before [to], or -1:
  /// a search that stops where the line does, as `indexOf` would not.
  static int _find(String held, int unit, int at, int to) {
    final end = to < held.length ? to : held.length;
    for (var here = at; here < end; here++) {
      if (held.codeUnitAt(here) == unit) {
        return here;
      }
    }
    return -1;
  }
}
