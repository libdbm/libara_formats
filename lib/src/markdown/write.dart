part of 'markdown.dart';

/// Writes a document read in another syntax as Markdown, walking its tree:
/// ported from markwrite's Markdown writer.
final class _Writer {
  _Writer(this.content);

  /// The document's content.
  final String content;

  /// Where the last numbered list written left off, for one that continues
  /// it. Markdown has no way to say `continue`, so it is said as a number.
  var _counted = 0;

  /// The blocks, each parted from the one before it by a blank line.
  static const _blocks = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol', //
    'pre', 'hr', 'table',
  };

  /// The content from [start] to [end], with [kids] in it; [indent] begins
  /// every line after the first.
  String render(int start, int end, List<Node> kids, String indent) {
    final written = StringBuffer();
    // The last two characters written, kept rather than read back out of
    // the buffer, which would copy everything written once per block; and
    // whether anything but white space has been, since a block parts from
    // words before it and there may be none.
    var tail = '';
    var spoken = false;
    // Whether what is written next begins a line: the block's first words,
    // or those after a line break.
    var line = true;
    // Whether the last thing written was a block, which what is not a block
    // after it stands apart from as a block would, or it runs on into it.
    var blocked = false;
    void part() {
      if (blocked && !tail.endsWith('\n\n')) {
        written.write(tail.endsWith('\n') ? '\n$indent' : '\n\n$indent');
        tail = '\n\n';
      }
      blocked = false;
    }

    var at = start;
    for (final kid in kids) {
      if (kid.start > at) {
        final said = _text(at, kid.start, indent, head: line);
        if (said.trim().isNotEmpty) {
          part();
        }
        line = false;
        written.write(said);
        tail = _last(tail, said);
        spoken = spoken || said.trim().isNotEmpty;
      }
      // A block stands apart from the one before it, by a blank line. Where
      // the source already put one between them, that is what stands there;
      // where it put a single line end, as roff does before a request, one
      // more is written, since one line end in Markdown runs on. A block
      // that says nothing gets nothing, since a paragraph holding one
      // picture is represented by the picture.
      final said = _element(kid, indent);
      final block = _blocks.contains(kid.name);
      if (block && spoken && said.isNotEmpty && !tail.endsWith('\n\n')) {
        written.write(tail.endsWith('\n') ? '\n$indent' : '\n\n$indent');
      } else if (!block && said.trim().isNotEmpty) {
        part();
      }
      if (said.isNotEmpty) {
        blocked = block;
      }
      // Two runs of `*` that meet read as one, as `***` and `**` do after
      // an em ending in a strong, so a space parts them.
      if (!block && tail.endsWith('*') && said.startsWith('*')) {
        written.write(' ');
        tail = _last(tail, ' ');
      }
      written.write(said);
      tail = _last(tail, said);
      spoken = spoken || said.trim().isNotEmpty;
      line = kid.name == 'br' || (line && said.isEmpty);
      at = kid.end;
    }
    if (end > at) {
      final said = _text(at, end, indent, head: line);
      if (said.trim().isNotEmpty) {
        part();
      }
      written.write(said);
    }
    return written.toString();
  }

  /// The last two characters of [tail] followed by [said].
  static String _last(String tail, String said) {
    final held = tail + said;
    return held.length > 2 ? held.substring(held.length - 2) : held;
  }

  /// The longest run of [character] in [text].
  static int _longest(String text, String character) {
    var longest = 0;
    var run = 0;
    for (var at = 0; at < text.length; at += 1) {
      run = text[at] == character ? run + 1 : 0;
      longest = max(longest, run);
    }
    return longest;
  }

  /// The words from [start] to [end], escaped, each line after the first
  /// under [indent]; where they are the [head] of a block, their first line
  /// is escaped as each line after it is, so it does not begin another.
  String _text(int start, int end, String indent, {bool head = false}) {
    final text = _escaped(content.substring(start, end), head: head);
    return indent.isEmpty ? text : text.replaceAll('\n', '\n$indent');
  }

  String _inside(Node node, String indent) =>
      render(node.start, node.end, node.kids, indent);

  String _element(Node node, String indent) {
    switch (node.name) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.name.substring(1));
        return '${'#' * level} ${_inside(node, indent)}';
      // HTML's b and i are emphasis too, which is how a browser and Google
      // Docs put it on the clipboard.
      case 'em' || 'i':
        return '*${_inside(node, indent)}*';
      case 'strong' || 'b':
        return '**${_inside(node, indent)}**';
      case 'code':
        // A fence longer than any run of backticks the code holds, and a
        // space inside each end where the code begins or ends with one, or
        // with spaces a read would take as the fence's.
        final code = content.substring(node.start, node.end);
        final fence = '`' * (_longest(code, '`') + 1);
        final padded =
            code.startsWith('`') ||
            code.endsWith('`') ||
            (code.length > 1 &&
                code.startsWith(' ') &&
                code.endsWith(' ') &&
                code.trim().isNotEmpty);
        return padded ? '$fence $code $fence' : '$fence$code$fence';
      case 'a':
        final title = node['title'];
        final said = title == null ? '' : ' "${title.replaceAll('"', r'\"')}"';
        return '[${_inside(node, indent)}]'
            '(${_destination(node['href'] ?? '')}$said)';
      case 'img':
        return '![${_escaped(node['alt'] ?? '')}]'
            '(${_destination(node['src'] ?? '')})';
      case 'p':
        // A paragraph is represented by standing on its own, which the blank
        // line between it and what comes next already says.
        return _inside(node, indent);
      case 'hr':
        return '---';
      case 'br':
        return '  \n$indent';
      case 'pre':
        final code = content.substring(node.start, node.end);
        final fenced = code.endsWith('\n') ? code : '$code\n';
        // A fence is longer than any run of backticks the code holds, or
        // the code would close it.
        final fence = '`' * max(3, _longest(code, '`') + 1);
        return '$fence\n$fenced$fence';
      case 'blockquote':
        final inner = _inside(node, indent);
        return '> ${inner.replaceAll('\n', '\n$indent> ')}';
      case 'ul' || 'ol':
        return _list(node, indent);
      case 'table':
        return _table(_rows(node), indent);
      case 'head' when node.start == node.end && node.kids.isEmpty:
        // HTML implies a head on every page, and one that holds nothing
        // says nothing a reader of Markdown would see.
        return '';
      default:
        // An element with content keeps the content and loses the name,
        // which is all Markdown can do for a vocabulary it does not know.
        // An element with no content would lose everything, so it is
        // written as a link standing in for itself and read back as one.
        return node.start == node.end && node.kids.isEmpty
            ? '[](${node.name} "${md.standing}")'
            : _inside(node, indent);
    }
  }

  /// A table's rows, read through the head, body and foot that group them,
  /// since HTML implies a body round rows a page writes bare.
  static List<Node> _rows(Node table) => [
    for (final kid in table.kids)
      if (kid.name == 'tr')
        kid
      else if (_grouping.contains(kid.name))
        for (final row in kid.kids)
          if (row.name == 'tr') row,
  ];

  /// The elements that group a table's rows.
  static const _grouping = {'thead', 'tbody', 'tfoot'};

  /// A table the extended way: a head, a line of dashes, then the rest.
  ///
  /// Extended Markdown has no way to say a table without a head, so the
  /// first row becomes one whether it was written as a head or not.
  String _table(List<Node> rows, String indent) {
    final written = StringBuffer();
    for (final (index, row) in rows.indexed) {
      final cells = [
        for (final cell in row.kids)
          if (cell.name == 'th' || cell.name == 'td') cell,
      ];
      if (index > 0) {
        written.write('\n$indent');
      }
      written
        ..write('| ')
        ..write(
          [for (final cell in cells) _celled(_inside(cell, ''))].join(' | '),
        )
        ..write(' |');
      if (index == 0) {
        written
          ..write('\n$indent| ')
          ..write(List.filled(cells.length, '---').join(' | '))
          ..write(' |');
      }
    }
    return written.toString();
  }

  /// A cell says nothing a row cannot hold: a bar would end it and a line
  /// end would end the row.
  static String _celled(String text) =>
      text.replaceAll('|', r'\|').replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

  String _list(Node list, String indent) {
    final ordered = list.name == 'ol';
    // Where the list counts from: on from the last numbered list where it
    // says `continue`, and where it says under `start`.
    final first = list['continue'] != null
        ? _counted + 1
        : int.tryParse(list['start']?.trim() ?? '') ?? 1;
    final written = StringBuffer();
    final items = list.kids;
    for (final (index, item) in items.indexed) {
      final marker = ordered ? '${first + index}. ' : '- ';
      if (index > 0) {
        written.write('\n$indent');
      }
      written
        ..write(marker)
        ..write(_inside(item, indent + ' ' * marker.length));
    }
    if (ordered) {
      _counted = first + items.length - 1;
    }
    return written.toString();
  }

  /// [text] with the characters Markdown would read as syntax escaped,
  /// and what would begin a block at the start of a line after the first,
  /// or of the first where it is the [head] of a block.
  static String _escaped(String text, {bool head = false}) {
    final escaped = text.replaceAllMapped(_syntax, (match) => '\\${match[0]}');
    return escaped.replaceAllMapped(
      head ? _heads : _lines,
      (match) => '${match[1]}${match[2]}\\${match[3]}',
    );
  }

  /// The characters Markdown reads as syntax wherever they stand.
  static final _syntax = RegExp(r'[\\`*_\[\]<&]');

  /// What begins a block at the start of a line: a heading's hash, a
  /// quote's angle, a bullet, a setext underline or a fence of tildes, or
  /// the stop or bracket after an ordered item's number; after the spaces
  /// that may stand before it.
  static final _lines = RegExp(
    r'(\n)( {0,3}(?:\d{1,9})?)([#>+=~-]|(?<=\d)[.)])',
  );

  /// [_lines], and at the start of the text.
  static final _heads = RegExp(
    r'(^|\n)( {0,3}(?:\d{1,9})?)([#>+=~-]|(?<=\d)[.)])',
  );
}
