part of 'latex.dart';

/// [value], read in another syntax, written as a LaTeX article.
Result<Sequence<int>> _written(Layered<int> value) =>
    nodes(value, 'latex').flatMap((tree) {
      final writer = _Writer(tree.content)
        ..render(0, tree.content.length, tree.roots);
      if (writer.fault case final fault?) {
        return Failure(Kind.invalid, 'latex: $fault');
      }
      return Success(
        Text.of(
          '\\documentclass{article}\n\\begin{document}\n'
          '${writer.written}\\end{document}\n',
        ),
      );
    });

/// Writes a document as LaTeX represents it, walking its tree: ported from
/// markwrite's LaTeX writer.
final class _Writer {
  _Writer(this.content);

  /// The document's content.
  final String content;

  /// Why the document cannot be written, once something has none.
  String? fault;

  final StringBuffer _out = StringBuffer();

  /// How many line ends the writing ends with.
  int _ends = 0;

  /// The space read between blocks, held until what follows says how much
  /// of it is wanted.
  String _pending = '';

  /// Whether the last thing written began an environment, which a block
  /// inside it needs no blank line to be parted from.
  bool _opened = false;

  /// Everything written, ending with a line end.
  String get written {
    _flush();
    if (_out.isNotEmpty && _ends == 0) {
      _write('\n');
    }
    return _out.toString();
  }

  /// The content from [start] to [end], with [kids] in it.
  void render(int start, int end, List<Node> kids) {
    var at = start;
    for (final kid in kids) {
      if (kid.start > at) {
        _words(at, kid.start);
      }
      _element(kid);
      at = kid.end;
    }
    if (end > at) {
      _words(at, end);
    }
  }

  void _inside(Node node) => render(node.start, node.end, node.kids);

  void _words(int start, int end) {
    final said = content.substring(start, end);
    if (said.trim().isEmpty) {
      _pending += said;
      return;
    }
    _flush();
    _write(_escaped(said));
  }

  void _write(String said) {
    if (said.isEmpty) {
      return;
    }
    _out.write(said);
    _opened = false;
    var tail = 0;
    while (tail < said.length && said[said.length - 1 - tail] == '\n') {
      tail += 1;
    }
    _ends = tail == said.length ? _ends + tail : tail;
  }

  void _flush() {
    _write(_pending);
    _pending = '';
  }

  /// Begins a block parted from what went before by [lines] line ends:
  /// nothing more where the writing ends with them, the space held where it
  /// makes them up, else that many and nothing else.
  void _block(int lines) {
    if (_out.isEmpty) {
      _pending = '';
      return;
    }
    final wanted = _opened ? 1 : lines;
    if (_ends >= wanted) {
      _pending = '';
      return;
    }
    if (_ends + '\n'.allMatches(_pending).length >= wanted) {
      _flush();
      return;
    }
    _pending = '';
    _write('\n' * (wanted - _ends));
  }

  void _element(Node node) {
    final name = switch (node.name) {
      'i' => 'em',
      'b' => 'strong',
      'tt' || 'kbd' || 'samp' => 'code',
      final held => held,
    };
    switch (name) {
      case 'br':
        _flush();
        _write('\\\\\n');
        return;
      case 'p':
        _block(2);
        _inside(node);
        return;
      case 'li':
        _block(1);
        _write(r'\item ');
        _inside(node);
        return;
      case 'dt':
        _block(1);
        _write(r'\item[');
        _inside(node);
        _flush();
        _write('] ');
        return;
      case 'dd':
        _inside(node);
        return;
      case 'pre':
        final said = content.substring(node.start, node.end);
        _block(1);
        _write(r'\begin{verbatim}');
        _write(said.startsWith('\n') ? said : '\n$said');
        _write(said.endsWith('\n') ? r'\end{verbatim}' : '\n\\end{verbatim}');
        return;
      case 'math' || 'equation':
        if (node['notation'] == 'eqn' || node.kids.isNotEmpty) {
          fault ??= 'a formula in eqn or MathML has no latex representation';
          return;
        }
        final said = content.substring(node.start, node.end);
        if (name == 'math') {
          _flush();
          _write('\$$said\$');
        } else {
          _block(1);
          _write('\\[$said\\]');
        }
        return;
      case 'img':
        final file = node['src'] ?? '';
        if (file.isEmpty || file.contains(_unfiled)) {
          fault ??= 'latex has no representation for a picture at "$file"';
          return;
        }
        _flush();
        _write('\\includegraphics{$file}');
        return;
      case 'table' || 'tr' || 'td' || 'th':
        fault ??= 'latex has no representation for $name';
        return;
      case 'comment':
        _block(1);
        for (final line
            in content.substring(node.start, node.end).split('\n')) {
          _write('% $line\n');
        }
        return;
      case 'q':
        _flush();
        _write('``');
        _inside(node);
        _flush();
        _write("''");
        return;
      case 'a' when node['href'] == null && node['id'] != null:
        // An anchor is a label, which LaTeX places where it stands; one
        // whose name an argument cannot hold is left out.
        if (!node['id']!.contains(_unfiled)) {
          _flush();
          _write('\\label{${node['id']}}');
        }
        return;
      case 'a'
          when (node['href']?.startsWith('#') ?? false) &&
              !node['href']!.substring(1).contains(_unfiled):
        // A link within the document is a reference to its label, which
        // shows what LaTeX numbers rather than the words linked.
        _flush();
        _write('\\ref{${node['href']!.substring(1)}}');
        return;
      case 'a':
        _flush();
        _write('\\href{${_linked(node['href'] ?? '')}}{');
        _inside(node);
        _flush();
        _write('}');
        return;
      case 'toc' || 'hr':
        return;
    }
    final notation = _notations[name];
    if (notation == null || name == 'br') {
      _inside(node);
      return;
    }
    final (opening, closing) = notation;
    if (opening.startsWith(r'\begin')) {
      _block(1);
      _write(opening);
      _opened = true;
      _inside(node);
      _block(1);
      _write(closing.substring(1));
      return;
    }
    _heading(name) ? _block(2) : _flush();
    _write(opening);
    _inside(node);
    _flush();
    _write(closing);
  }

  static bool _heading(String name) =>
      name == 'title' ||
      name == 'author' ||
      (name.length == 2 && name.startsWith('h'));

  /// Words as LaTeX represents them: every character it reads as syntax
  /// escaped, and a no-break space as a tie.
  static String _escaped(String text) {
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      switch (unit) {
        case 0x5C:
          out.write(r'\textbackslash{}');
        case 0x7E:
          out.write(r'\textasciitilde{}');
        case 0x60:
          out.write(r'\textasciigrave{}');
        case 0x5E:
          out.write(r'\textasciicircum{}');
        case 0xA0:
          out.write('~');
        case 0x7B || 0x7D || 0x24 || 0x26 || 0x23 || 0x5F || 0x25:
          out
            ..write(r'\')
            ..writeCharCode(unit);
        default:
          out.writeCharCode(unit);
      }
    }
    return out.toString();
  }
}

/// What a picture's file or a label's name cannot hold to be written as an
/// argument: what would close it, begin a command or a comment, or stand
/// for a parameter.
final _unfiled = RegExp(r'[{}\\%#]');
