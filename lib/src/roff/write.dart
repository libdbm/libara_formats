part of 'roff.dart';

/// [value], read in another syntax, written as the roff package [syntax],
/// which represents its elements as [notations] say.
Result<Sequence<int>> _written(
  String syntax,
  Map<String, (String, String)> notations,
  Layered<int> value,
) => nodes(value, syntax).flatMap((tree) {
  final writer = _Writer(syntax, notations, tree.content);
  final written = writer.render(0, tree.content.length, tree.roots);
  if (writer.fault case final fault?) {
    return Failure(Kind.invalid, '$syntax: $fault');
  }
  // A formula in running words needs the delimiters said once, at the head,
  // in an equation of their own.
  return Success(
    Text.of(writer.delimited ? '.EQ\ndelim \$\$\n.EN\n$written' : written),
  );
});

/// What an argument is written as: a line end as a space, since a request
/// is one line, and quoted where it holds a space or a tab or is nothing,
/// so that it stays one argument, a quote doubled as roff has it.
String _quoted(String said) {
  final held = said.replaceAll(RegExp(r'[\r\n]+'), ' ');
  return held.isEmpty || held.contains(' ') || held.contains('\t')
      ? '"${held.replaceAll('"', '""')}"'
      : held;
}

/// [value], which says something and represents nothing, as an argument: a
/// backslash as the escape that shows one.
String _argument(String value) => _quoted(value.replaceAll(r'\', r'\e'));

/// The names the glyph table represents each character by, for writing.
final Map<String, String> _named = {
  for (final MapEntry(key: name, value: said) in _glyphs.entries)
    if (said.length == 1 && said.codeUnitAt(0) > 0x7E && name.length <= 2)
      said: name,
};

/// Writes a document as a roff package represents it, walking its tree: ported
/// from markwrite's roff writer.
final class _Writer {
  _Writer(this.syntax, this.notations, this.content);

  /// The package's name.
  final String syntax;

  /// How the package represents each element it can, the faces aside.
  final Map<String, (String, String)> notations;

  /// The document's content.
  final String content;

  /// Why the document cannot be written, once something has none.
  String? fault;

  /// Whether a formula in running words was written, which wants the
  /// delimiters declared.
  bool delimited = false;

  /// The last character written, so a request begins its own line.
  String _tail = '\n';
  bool _begun = false;

  /// The faces standing open in what is being written, so a face closes
  /// back to the one outside it: with `\fP` where nothing was set inside
  /// it, since the previous face is then the one outside, and by name
  /// otherwise, since a change inside moved what the previous face is.
  final List<({String name, bool nested})> _open = [];

  /// The lists being written, innermost last, each with the items of a
  /// numbered one counted so far.
  final List<int?> _lists = [];

  (String, String)? _notation(String name) => _faces[name] ?? notations[name];

  /// The content from [start] to [end], with [kids] in it.
  String render(int start, int end, List<Node> kids) {
    final written = StringBuffer();
    var at = start;
    for (final kid in kids) {
      if (kid.start > at) {
        _between(written, at, kid.start, kid);
      }
      _element(written, kid);
      at = kid.end;
    }
    if (end > at) {
      _between(written, at, end, null);
    }
    return written.toString();
  }

  /// The words from [start] to [end], before [next]. Where they are
  /// nothing but the space another syntax leaves between its blocks and a
  /// request line follows, one line end, since a blank line is a paragraph
  /// break to roff and the request already parts the blocks; before a
  /// paragraph no request opens, the space stands, since it parts it.
  void _between(StringBuffer written, int start, int end, Node? next) {
    final said = content.substring(start, end);
    final requested =
        next == null ||
        (next['implied'] == null &&
            (_notation(next.name)?.$1.startsWith('.') ?? false));
    if (said.contains('\n') && said.trim().isEmpty && requested) {
      if (_tail != '\n') {
        _write(written, '\n');
      }
    } else {
      _write(written, _escaped(said));
    }
  }

  void _write(StringBuffer written, String said) {
    if (said.isEmpty) {
      return;
    }
    written.write(said);
    _tail = said[said.length - 1];
    _begun = true;
  }

  void _line(StringBuffer written) {
    if (_begun && _tail != '\n') {
      _write(written, '\n');
    }
  }

  String _inside(Node node) => render(node.start, node.end, node.kids);

  /// The cells of each row of [table], whatever groups the rows stand in.
  static List<List<Node>> _rows(Node table) => [
    for (final kid in table.kids)
      if (kid.name == 'tr')
        [
          for (final cell in kid.kids)
            if (cell.name == 'td' || cell.name == 'th') cell,
        ]
      else
        ..._rows(kid),
  ];

  /// What [cell] holds as a tbl cell: as it stands where it is one line of
  /// words, and a text block where tbl would read it otherwise.
  String _cell(Node cell) {
    final said = _inside(cell);
    final held = said.endsWith('\n')
        ? said.substring(0, said.length - 1)
        : said;
    final plain =
        !held.contains('\n') &&
        !held.contains('\t') &&
        !held.startsWith('.') &&
        !held.startsWith("'") &&
        !held.startsWith('T{') &&
        held.trim() != '_' &&
        held.trim() != '=';
    return plain ? held : 'T{\n$held\nT}';
  }

  /// An item's request, saying [tag].
  String _item(String tag) {
    final (opening, _) = notations['li']!;
    return '${opening.trimRight()} ${tag.isEmpty ? '' : _quoted(tag)}';
  }

  void _element(StringBuffer written, Node node) {
    final name = switch (node.name) {
      'i' => 'em',
      'b' => 'strong',
      'tt' || 'kbd' || 'samp' => 'code',
      final held => held,
    };
    switch (name) {
      case 'br':
        _line(written);
        _write(written, '.br\n');
        return;
      case 'head':
        final said = [
          for (final held in const [
            'name',
            'section',
            'date',
            'source',
            'manual',
          ])
            if (node[held] case final String value) _argument(value),
        ];
        // Only a manual page has a head to write.
        if (syntax == 'man' && said.isNotEmpty) {
          _line(written);
          _write(written, '.TH ${said.join(' ')}');
        }
        return;
      case 'dt':
        _line(written);
        final term = _inside(node);
        _write(written, syntax == 'man' ? '.TP\n$term' : _item(term));
        return;
      case 'dd':
        _line(written);
        _write(written, _inside(node));
        return;
      case 'li':
        _line(written);
        _write(written, '${_item(_tag(node))}\n');
        _write(written, _inside(node));
        return;
      case 'math':
        if (node['notation'] != 'eqn') {
          fault ??= 'a formula in TeX or MathML has no $syntax representation';
          return;
        }
        delimited = true;
        _write(written, '\$${content.substring(node.start, node.end)}\$');
        return;
      case 'table':
        _line(written);
        final rows = _rows(node);
        final columns = rows.fold(1, (most, row) => max(most, row.length));
        _write(written, '.TS\n${List.filled(columns, 'l').join(' ')}.\n');
        for (final row in rows) {
          _write(
            written,
            '${[for (final cell in row) _cell(cell)].join('\t')}\n',
          );
        }
        _write(written, '.TE\n');
        return;
      case 'img' || 'tr' || 'td' || 'th':
        fault ??= '$syntax has no representation for $name';
        return;
      case 'comment':
        _line(written);
        for (final line in _inside(node).split('\n')) {
          _write(written, '.\\" $line\n');
        }
        return;
      case 'q':
        _write(written, '\\(lq${_inside(node)}\\(rq');
        return;
      case 'ul' || 'ol':
        _lists.add(name == 'ol' ? 0 : null);
        _write(written, _inside(node));
        _lists.removeLast();
        return;
      case 'toc' || 'hr':
        return;
    }
    // A paragraph no request opened is its words, as it was read.
    if (name == 'p' && node['implied'] != null) {
      _line(written);
      _write(written, _inside(node));
      return;
    }
    final notation =
        _notation(name) ??
        (name == 'blockquote' || name == 'footnote' ? _notation('div') : null);
    if (notation == null) {
      _write(written, _inside(node));
      return;
    }
    final (opening, closing) = notation;
    if (!opening.startsWith('.')) {
      if (_open.isNotEmpty) {
        _open[_open.length - 1] = (name: _open.last.name, nested: true);
      }
      _open.add((name: name, nested: false));
      _write(written, opening);
      _write(written, _inside(node));
      final held = _open.removeLast();
      _write(
        written,
        !held.nested
            ? closing
            : _open.isEmpty
            ? r'\fR'
            : _faces[_open.last.name]!.$1,
      );
      return;
    }
    if (name == 'equation' && node['notation'] != 'eqn') {
      fault ??= 'a formula in TeX or MathML has no $syntax representation';
      return;
    }
    _line(written);
    if (name == 'a') {
      _write(written, '$opening${_argument(node['href'] ?? '')}\n');
    } else {
      _write(written, opening);
    }
    final inner = _inside(node);
    // A heading's words stand on the request's own line, one argument in
    // me, which quotes them where they hold a space.
    final lined = inner.replaceAll('\n', ' ');
    _write(
      written,
      opening.endsWith('\n')
          ? inner
          : syntax == 'me'
          ? _quoted(lined)
          : lined,
    );
    if (closing.isNotEmpty) {
      _line(written);
      _write(written, closing);
    }
  }

  /// What an item's marker is: what it says, else a figure where its list
  /// counts, else a bullet.
  String _tag(Node item) {
    if (item['tag'] case final String said) {
      return said;
    }
    if (_lists.lastOrNull case final int count) {
      _lists.last = count + 1;
      return '${count + 1}.';
    }
    return r'\(bu';
  }

  /// [text] as roff represents it: a backslash escaped, a control character at
  /// the head of a line kept from being one, and a character outside ASCII
  /// said by its glyph name.
  String _escaped(String text) {
    final out = StringBuffer();
    var tail = _tail;
    for (final rune in text.runes) {
      final one = String.fromCharCode(rune);
      if (rune == 0x5C) {
        out.write(r'\e');
      } else if ((rune == 0x2E || rune == 0x27) && tail == '\n') {
        out.write('\\&$one');
      } else if (rune > 0x7E) {
        final named = _named[one];
        out.write(
          named != null
              ? '\\($named'
              : '\\[u${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}]',
        );
      } else {
        out.write(one);
      }
      tail = one;
    }
    return out.toString();
  }
}
