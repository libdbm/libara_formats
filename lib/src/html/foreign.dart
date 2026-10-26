part of 'html.dart';

/// Markup somebody else wrote, read as HTML and written again as the
/// HTML a document is made of.
abstract final class Foreign {
  /// Markup somebody else wrote, cut down to what this application writes.
  ///
  /// What a browser puts on the clipboard is a page: a meta tag saying what it
  /// is encoded in, divs holding the layout the site was built with, and a
  /// style attribute on nearly everything saying what that site's own
  /// stylesheet had resolved to. None of it belongs in a document that has a
  /// look of its own, and a paste that carried it would set one paragraph in
  /// Arial on a grey ground in the middle of a book.
  ///
  /// So what survives is the structure and nothing about the appearance: the
  /// blocks, the emphasis, the lists, the links and the pictures. That is what
  /// every word processor calls pasting and matching the style, and it is the
  /// kind of paste this offers by default, since the look belongs to the
  /// document being pasted into. Emphasis represented as a style, which is
  /// how a browser and Google Docs represent it, is emphasis all the same and
  /// comes through as the element that says so.
  ///
  /// Nothing where the markup cannot be read at all, and what asks then pastes
  /// the words as words, which is what it did before there was anything else
  /// to paste.
  static String? cleaned(String source) =>
      _Reading(source, keeping: false).read();

  /// Markup somebody else wrote, with a fixed set of its formatting kept as
  /// direct formatting on the elements that survive.
  ///
  /// What [cleaned] keeps, and beside it what a reader asking to keep the
  /// formatting means: the weight, the slant, the underline and the strike as
  /// the elements that say them, and the colour, the size and the alignment as
  /// a `style` attribute the document's own sheet reads back. The face and the
  /// rest of the page's cascade still go, since a paragraph in a book is set
  /// in the book's face whatever it was copied from.
  static String? kept(String source) => _Reading(source, keeping: true).read();

  /// Markup somebody else wrote, read as a document to be worked on rather than
  /// as something to paste.
  ///
  /// What [kept] keeps, and the class each element was in besides. A paste is
  /// dropped into a document that already has a look and a class it cannot name
  /// a rule for is noise; a file is opened with the page's own stylesheet
  /// beside it, and the class is what a rule in that stylesheet is keyed on.
  /// Word's HTML export says which of its styles every paragraph was in that
  /// way and no other.
  static String? imported(String source) =>
      _Reading(source, keeping: true, classed: true).read();
}

/// One pass over the tokens of a page, writing what is kept.
final class _Reading {
  final String source;

  /// Whether the look a fixed set of properties says is carried over as
  /// direct formatting, or only the structure.
  final bool keeping;

  /// Whether the class each element was in is carried over, which a reader
  /// keeping the page's own stylesheet wants and a paste does not.
  final bool classed;

  _Reading(this.source, {required this.keeping, this.classed = false});

  final StringBuffer out = StringBuffer();

  /// What is open and has been written, so that what is written closes: a
  /// page's markup is full of tags nothing closes, and a fragment that leaves
  /// an element open is a fragment that swallows the document it lands in.
  ///
  /// Each entry is the page's element and the names written for it, since
  /// one span may have become `<b><i>` and one paragraph a list item.
  final List<({String name, List<String> wrote})> open = [];

  /// The lists open around Word's list paragraphs, outermost first, since
  /// Word writes a list as paragraphs that each say which list and which
  /// level they belong to and never writes the list itself.
  final List<({String kind, String id})> lists = [];

  /// The Word list paragraph whose item is not yet written, which waits for
  /// its marker to say what kind of list it is in: its level, and the list
  /// Word says it belongs to.
  ({int level, String id})? pending;

  /// Whether the walk stands between Word's `[if !supportLists]` and
  /// `[endif]`, where the marker is written out for a reader that does not
  /// know lists; what stands there is read for its kind and not written.
  bool hidden = false;
  final StringBuffer marker = StringBuffer();

  /// The element whose whole content is somebody else's and goes: a page's
  /// head, its stylesheet, its script; and how deep the walk stands in
  /// elements of that name, so the right end tag ends it.
  String? muted;
  int depth = 0;

  /// Whether the last thing written was a block's tag, so that the blank
  /// run a page puts between blocks is not written into the document.
  bool blocked = true;

  /// The page's tokens, each with what it is called and its text.
  late final List<_Piece> pieces;

  String? read() {
    final read = switch (const HTML().decode(Text.of(source))) {
      Success(:final value) => value,
      Failure() => null,
    };
    if (read == null) {
      return null;
    }
    pieces = [
      for (final token in read.layer(2).items.cast<ARange>())
        _Piece(
          '${token.get('')}',
          String.fromCharCodes(read.slice(token).items),
          token,
        ),
    ];
    for (final (index, piece) in pieces.indexed) {
      final name = piece.name;
      if (name == '#comment') {
        _comment(piece.said);
        continue;
      }
      if (name == prose || name == '#entity') {
        _text(piece.said);
        continue;
      }
      if (hidden || name.startsWith('#')) {
        continue;
      }
      if (muted case final mute?) {
        if (name == mute) {
          switch (piece.part) {
            case _Part.start:
              depth++;
            case _Part.end:
              depth == 0 ? muted = null : depth--;
            case _Part.empty:
              break;
          }
        }
        continue;
      }
      switch (piece.part) {
        case _Part.start:
          _start(piece, name, index);
        case _Part.end:
          _end(name);
        case _Part.empty:
          if (_kept.contains(name)) {
            out.write('<$name${_attributes(piece, name)}/>');
            blocked = false;
          }
      }
    }
    while (open.isNotEmpty) {
      _close(open.removeLast());
    }
    _unlisted();
    final said = out.toString();
    return said.trim().isEmpty ? null : said;
  }

  void _text(String text) {
    if (hidden) {
      marker.write(text);
      return;
    }
    if (muted != null || (blocked && text.trim().isEmpty)) {
      return;
    }
    if (pending != null) {
      // A list paragraph with no marker written out, which Word does not
      // write but a page copying its markup might.
      _item('ul');
    }
    out.write(text);
    blocked = false;
  }

  void _comment(String said) {
    if (said.contains('[if !supportLists]')) {
      hidden = true;
      marker.clear();
    } else if (hidden && said.contains('[endif]')) {
      hidden = false;
      final stripped = marker.toString().replaceAll(RegExp(r'<[^>]*>'), '');
      if (pending != null) {
        _item(_ordered.hasMatch(stripped) ? 'ol' : 'ul');
      }
    }
  }

  /// The level a Word list paragraph says it stands at.
  static final RegExp _level = RegExp(r'level(\d+)');

  /// The list a Word list paragraph says it belongs to.
  static final RegExp _list = RegExp(r'lfo\d+');

  /// The deepest level Word writes a list at.
  static const _deepest = 9;

  /// A marker that counts, as against a bullet: a numeral or a letter and
  /// the stop or bracket after it.
  static final RegExp _ordered = RegExp(r'^\s*(\d+|[a-zA-Z])[.)]');

  void _start(_Piece token, String name, int index) {
    final style = _declared(token.plain('style') ?? '');
    if (_muted.contains(name)) {
      muted = name;
      depth = 0;
      return;
    }
    // Google Docs wraps what it copies in a `b` that says it is not bold,
    // which is a wrapper and not an emphasis.
    if ((name == 'b' || name == 'strong') && _light(style['font-weight'])) {
      open.add((name: name, wrote: const []));
      return;
    }
    final listed = style['mso-list'];
    if (name == 'p' && listed != null) {
      pending = (
        level: (int.tryParse(_level.firstMatch(listed)?.group(1) ?? '') ?? 1)
            .clamp(1, _deepest),
        id: _list.firstMatch(listed)?.group(0) ?? '',
      );
      open.add((name: name, wrote: ['li']));
      return;
    }
    // A div holding words rather than blocks is a paragraph, which is how a
    // mail client and a browser write one.
    final written = name == 'div' && _wordy(index) ? 'p' : name;
    if (!_kept.contains(written) && name != 'span') {
      open.add((name: name, wrote: const []));
      return;
    }
    final wrote = <String>[];
    if (_standing.contains(written)) {
      _blocked(written);
      if (_kept.contains(written)) {
        out.write('<$written${_attributes(token, written, style: style)}>');
        wrote.add(written);
        blocked = true;
      }
    } else {
      final own = _styled(style, inline: true);
      if (name != 'span') {
        out.write('<$name${_attributes(token, name, style: style)}>');
        wrote.add(name);
      } else if (own.isNotEmpty) {
        out.write('<span style="${_quoted(own)}">');
        wrote.add('span');
      }
      // The emphasis the style represents, less what the element and the ones
      // round it already say: a strong that says it is bold is bold once,
      // and a link is underlined by nature.
      final said = {
        for (final held in open) ...held.wrote.map(_says),
        _says(name),
      };
      for (final emphasis in _emphasised(style)) {
        if (!said.contains(emphasis)) {
          out.write('<$emphasis>');
          wrote.add(emphasis);
        }
      }
      blocked = false;
    }
    open.add((name: name, wrote: wrote));
  }

  void _end(String name) {
    if (open.isNotEmpty && open.last.name == name) {
      _close(open.removeLast());
    }
  }

  void _close(({String name, List<String> wrote}) held) {
    if (pending != null && held.wrote.contains('li')) {
      // An item with nothing in it, closed before any marker or word came.
      pending = null;
      return;
    }
    for (final name in held.wrote.reversed) {
      out.write('</$name>');
      if (_standing.contains(name)) {
        blocked = true;
      }
    }
  }

  /// The emphasis an element says by being what it is.
  static String _says(String name) => switch (name) {
    'b' ||
    'strong' ||
    'h1' ||
    'h2' ||
    'h3' ||
    'h4' ||
    'h5' ||
    'h6' ||
    'th' => 'b',
    'i' || 'em' => 'i',
    'u' || 'a' => 'u',
    's' || 'del' => 's',
    _ => '',
  };

  /// Opens the lists a Word item at [pending]'s level stands in, closing
  /// deeper ones and one of another kind or another list at its own level,
  /// and writes the item.
  void _item(String kind) {
    final (:level, :id) = pending!;
    pending = null;
    while (lists.length > level) {
      out.write('</${lists.removeLast().kind}>');
    }
    if (lists.length == level &&
        (lists.last.kind != kind || lists.last.id != id)) {
      out.write('</${lists.removeLast().kind}>');
    }
    while (lists.length < level) {
      out.write('<$kind>');
      lists.add((kind: kind, id: id));
    }
    out.write('<li>');
    blocked = true;
  }

  /// A block of the page's own closes whatever Word lists stand open.
  void _blocked(String name) {
    if (name != 'li' && !_nesting.contains(name)) {
      _unlisted();
    }
  }

  void _unlisted() {
    while (lists.isNotEmpty) {
      out.write('</${lists.removeLast().kind}>');
      blocked = true;
    }
  }

  /// Whether the div starting at [index] holds words and no block of its
  /// own before it closes.
  bool _wordy(int index) => _wordies[index] ?? false;

  /// Whether each div holds words and no block, by the index of its start,
  /// read in one pass: what a div holds, the div around it holds too.
  late final Map<int, bool> _wordies = () {
    final wordies = <int, bool>{};
    final open = <({int index, bool words, bool blocks})>[];
    void close() {
      final div = open.removeLast();
      wordies[div.index] = div.words && !div.blocks;
      if (open.isNotEmpty) {
        final outer = open.removeLast();
        open.add((
          index: outer.index,
          words: outer.words || div.words,
          blocks: outer.blocks || div.blocks,
        ));
      }
    }

    void mark({bool words = false, bool blocks = false}) {
      if (open.isNotEmpty) {
        final div = open.removeLast();
        open.add((
          index: div.index,
          words: div.words || words,
          blocks: div.blocks || blocks,
        ));
      }
    }

    for (final (index, piece) in pieces.indexed) {
      final name = piece.name;
      if (name == prose || name == '#entity' || name == 'br' || name == 'img') {
        mark(words: true);
      }
      if (_standing.contains(name) && piece.part == _Part.start) {
        mark(blocks: true);
      }
      if (name == 'div') {
        if (piece.part == _Part.start) {
          open.add((index: index, words: false, blocks: false));
        } else if (piece.part == _Part.end && open.isNotEmpty) {
          close();
        }
      }
    }
    while (open.isNotEmpty) {
      close();
    }
    return wordies;
  }();

  /// The attributes an element keeps, which are the ones that say what it
  /// is rather than what it looks like, and the look that is kept as a
  /// style where the reader asked for it.
  String _attributes(
    _Piece token,
    String name, {
    Map<String, String> style = const {},
  }) {
    final wanted = switch (name) {
      'a' => const ['href'],
      'img' => const ['src', 'alt'],
      'td' || 'th' => const ['colspan', 'rowspan'],
      _ => const <String>[],
    };
    final out = StringBuffer();
    for (final held in wanted) {
      final value = token.plain(held);
      // A picture inlined as data is a picture, which is how LibreOffice
      // pastes one; on a link the same scheme would run.
      if (value != null &&
          value.isNotEmpty &&
          (!runs(value) ||
              (name == 'img' && held == 'src' && _inlined.hasMatch(value)))) {
        out.write(' $held="${_quoted(value)}"');
      }
    }
    if (classed) {
      final held = token.plain('class');
      if (held != null && held.trim().isNotEmpty) {
        out.write(' class="${_quoted(held.trim())}"');
      }
    }
    final own = _styled(style, inline: !_standing.contains(name), name: name);
    if (own.isNotEmpty) {
      out.write(' style="${_quoted(own)}"');
    }
    return out.toString();
  }

  /// The style a kept element carries: the alignment of a block, and where
  /// the formatting is kept, the colour and the size, and on a block the
  /// weight and slant too, since a block has no element to say them with.
  String _styled(
    Map<String, String> style, {
    required bool inline,
    String name = '',
  }) {
    if (!keeping) {
      return '';
    }
    final held = <String>[
      if (!inline && _aligned.contains(style['text-align']))
        'text-align:${style['text-align']}',
      if (_sized(style['font-size'])) 'font-size:${style['font-size']}',
      if (_coloured(style['color'])) 'color:${style['color']}',
      if (!inline) ...[
        if (_heavy(style['font-weight']) && _says(name) != 'b')
          'font-weight:bold',
        if (style['font-style'] == 'italic') 'font-style:italic',
        if (style['text-decoration']?.contains('underline') ?? false)
          'text-decoration:underline',
        if (style['text-decoration']?.contains('line-through') ?? false)
          'text-decoration:line-through',
      ],
    ];
    return held.join(';');
  }

  /// The emphasis a run's style represents, as the elements that say it.
  static List<String> _emphasised(Map<String, String> style) => [
    if (_heavy(style['font-weight'])) 'b',
    if (style['font-style'] == 'italic') 'i',
    if (style['text-decoration']?.contains('underline') ?? false) 'u',
    if (style['text-decoration']?.contains('line-through') ?? false) 's',
  ];

  static bool _heavy(String? weight) =>
      weight == 'bold' ||
      weight == 'bolder' ||
      (int.tryParse(weight ?? '') ?? 0) >= 600;

  static bool _light(String? weight) =>
      weight == 'normal' || (int.tryParse(weight ?? '') ?? 700) < 600;

  static bool _sized(String? size) =>
      size != null && RegExp(r'^\d+(\.\d+)?(px|pt|em)$').hasMatch(size);

  static bool _coloured(String? color) =>
      color != null && RegExp(r'^(#[0-9a-f]{3,8}|[a-z]+)$').hasMatch(color);

  static const Set<String> _aligned = {'left', 'right', 'center', 'justify'};

  /// A style attribute as its declarations, lowercased.
  static Map<String, String> _declared(String style) => {
    for (final one in style.split(';'))
      if (one.indexOf(':') case final at when at > 0)
        one.substring(0, at).trim().toLowerCase(): one
            .substring(at + 1)
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s*!important$'), ''),
  };
}

/// The elements a paste keeps.
///
/// What a document is made of rather than what a page is made of: the blocks,
/// the emphasis, the lists, the tables, the links and the pictures. A div, a
/// span, a meta and a script are structure of somebody else's making and go.
const Set<String> _kept = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'em',
  'i',
  'strong',
  'b',
  'u',
  's',
  'del',
  'ins',
  'code',
  'pre',
  'sub',
  'sup',
  'a',
  'ul',
  'ol',
  'li',
  'blockquote',
  'br',
  'table',
  'tr',
  'td',
  'th',
  'img',
};

/// The kept elements that stand as blocks.
const Set<String> _standing = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'ul',
  'ol',
  'li',
  'blockquote',
  'table',
  'tr',
  'td',
  'th',
};

/// The blocks that may stand inside a Word list without closing it.
const Set<String> _nesting = {'ul', 'ol'};

/// The elements whose whole content is a page's and not a document's.
const Set<String> _muted = {'head', 'style', 'script', 'title', 'xml'};

/// A picture inlined as data, in a kind that is only ever a picture: an SVG
/// can carry script, and is refused as any other data is.
final RegExp _inlined = RegExp(
  r'^\s*data:image/(png|jpeg|gif|webp);base64,',
  caseSensitive: false,
);

String _quoted(String held) => held
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('"', '&quot;');

/// What part a tag plays, read off its text as the tokenizer read it.
enum _Part { start, end, empty }

/// One of the page's tokens: what it is called, its text, and the range
/// saying its attributes.
final class _Piece {
  _Piece(this.name, this.said, this.range);

  final String name;
  final String said;
  final ARange range;

  /// An end tag, a tag that stands alone, or one that starts an element. A
  /// void element, an element read whole as one token and a tag closing
  /// itself stand alone.
  late final _Part part = said.startsWith('</')
      ? _Part.end
      : _voids.contains(name) ||
            _raw.contains(name) ||
            name == 'plaintext' ||
            said.endsWith('/>')
      ? _Part.empty
      : _Part.start;

  /// What the attribute [key] reads as, its references resolved.
  String? plain(String key) => range.get(key)?.toString();
}
