part of 'latex.dart';

/// What the reading marks: an element's opening or closing markup, an
/// escape showing what it shows, or a comment.
enum _Is { open, close, shown, comment }

/// One thing the reading marks, from [start] for [length].
final class _Event {
  _Event(this.start, this.length, this.name, this.said, this.kind);

  final int start;
  final int length;
  final String name;

  /// What it says.
  final Map<String, String> said;

  final _Is kind;

  /// This, saying [value] under [key] besides what it says: what a table's
  /// rule adds to a row already read.
  _Event adding(String key, String value) =>
      _Event(start, length, name, {...said, key: value}, kind);
}

/// Commands whose one braced argument is an element.
const Map<String, String> _wrapping = {
  'emph': 'em',
  'textit': 'em',
  'textsl': 'em',
  'textbf': 'strong',
  'texttt': 'code',
  'underline': 'u',
  'textsuperscript': 'sup',
  'textsubscript': 'sub',
  'footnote': 'footnote',
  'thanks': 'footnote',
};

/// Commands whose argument is a block of its own: the headings, and the
/// title and the author.
const Map<String, String> _headings = {
  'part': 'h1',
  'chapter': 'h1',
  'section': 'h1',
  'subsection': 'h2',
  'subsubsection': 'h3',
  'paragraph': 'h4',
  'subparagraph': 'h5',
  'title': 'title',
  'author': 'author',
};

/// Declarations, which set the rest of the group they stand in.
const Map<String, String> _declarations = {
  'em': 'em',
  'it': 'em',
  'itshape': 'em',
  'sl': 'em',
  'slshape': 'em',
  'bf': 'strong',
  'bfseries': 'strong',
  'tt': 'code',
  'ttfamily': 'code',
};

/// Environments, by the element each is read as. One not here is a division
/// carrying its name as its class.
const Map<String, String> _environments = {
  'itemize': 'ul',
  'enumerate': 'ol',
  'description': 'dl',
  'quote': 'blockquote',
  'quotation': 'blockquote',
  'verse': 'blockquote',
  'abstract': 'abstract',
  'document': 'document',
  'thebibliography': 'ol',
  'tabular': 'table',
  'tabular*': 'table',
  'tabularx': 'table',
  'longtable': 'table',
};

/// The rules a table draws between its rows, by the weight each names: a
/// row asks for it above or below itself, and a sheet draws the weight.
const Map<String, String> _rules = {
  'toprule': 'heavy',
  'bottomrule': 'heavy',
  'midrule': 'light',
  'hline': 'thin',
};

/// Environments whose content is read as it stands, through their end.
const Map<String, String> _verbatim = {
  'verbatim': 'pre',
  'verbatim*': 'pre',
  'Verbatim': 'pre',
  'lstlisting': 'pre',
  'minted': 'pre',
  'tikzpicture': 'tikzpicture',
  'equation': 'equation',
  'equation*': 'equation',
  'align': 'equation',
  'align*': 'equation',
  'gather': 'equation',
  'gather*': 'equation',
  'multline': 'equation',
  'multline*': 'equation',
  'flalign': 'equation',
  'flalign*': 'equation',
  'eqnarray': 'equation',
  'eqnarray*': 'equation',
  'displaymath': 'equation',
};

/// Environments read as comments: the comment package's, and acmart's
/// CCSXML, which holds the classification its `\ccsdesc` commands show.
const Set<String> _commented = {'comment', 'CCSXML'};

/// Commands that define a command, which shows what it is defined as
/// where that is words alone.
const Set<String> _commanding = {
  'newcommand',
  'renewcommand',
  'providecommand',
};

/// Commands whose arguments are syntax, all of which shows nothing:
/// among them acmart's publication data, which its class sets in the
/// margins and footers rather than in the words.
const Set<String> _silent = {
  'setcopyright',
  'setcctype',
  'settopmatter',
  'copyrightyear',
  'acmConference',
  'acmBooktitle',
  'acmJournal',
  'acmYear',
  'acmVolume',
  'acmNumber',
  'acmArticle',
  'acmMonth',
  'acmPrice',
  'acmDOI',
  'acmISBN',
  'acmSubmissionID',
  'received',
  'startPage',
  'AtBeginDocument',
  'documentclass',
  'usepackage',
  'RequirePackage',
  'newcommand',
  'renewcommand',
  'providecommand',
  'newenvironment',
  'renewenvironment',
  'newtheorem',
  'date',
  'index',
  'input',
  'include',
  'bibliography',
  'bibliographystyle',
  'setlength',
  'addtolength',
  'setcounter',
  'addtocounter',
  'pagestyle',
  'thispagestyle',
  'vspace',
  'hspace',
  'graphicspath',
  'hypersetup',
  'cline',
  'addlinespace',
};

/// acmart's front matter: commands whose one braced argument is an
/// element, named as HTML names it where it can, with what each says of
/// itself.
const Map<String, (String, Map<String, String>)> _matter = {
  'affiliation': ('address', {}),
  'institution': ('span', {'class': 'institution'}),
  'department': ('span', {'class': 'department'}),
  'streetaddress': ('span', {'class': 'streetaddress'}),
  'city': ('span', {'class': 'city'}),
  'state': ('span', {'class': 'state'}),
  'postcode': ('span', {'class': 'postcode'}),
  'country': ('span', {'class': 'country'}),
  'authornote': ('footnote', {}),
  'keywords': ('div', {'class': 'keywords'}),
  'ccsdesc': ('div', {'class': 'ccsdesc'}),
};

/// Commands whose argument is a key, shown as it stands between what each
/// shows for its braces.
const Map<String, (String, String)> _keyed = {
  'cite': ('[', ']'),
  'citep': ('(', ')'),
  'citet': ('', ''),
};

/// The characters the symbol commands represent.
const Map<String, String> _symbols = {
  'LaTeX': 'LaTeX',
  'TeX': 'TeX',
  'ldots': '…',
  'dots': '…',
  'textbackslash': r'\',
  'textasciitilde': '~',
  'textasciicircum': '^',
  'textasciigrave': '`',
  'textbar': '|',
  'textless': '<',
  'textgreater': '>',
  'textendash': '–',
  'textemdash': '—',
  'textquoteleft': '‘',
  'textquoteright': '’',
  'textquotedblleft': '“',
  'textquotedblright': '”',
  'S': '§',
  'P': '¶',
  'copyright': '©',
  'textregistered': '®',
  'texttrademark': '™',
  'dag': '†',
  'ddag': '‡',
  'pounds': '£',
  'ss': 'ß',
  'ae': 'æ',
  'AE': 'Æ',
  'oe': 'œ',
  'OE': 'Œ',
  'o': 'ø',
  'O': 'Ø',
  'aa': 'å',
  'AA': 'Å',
  'l': 'ł',
  'L': 'Ł',
  'quad': '\u2003',
  'qquad': '\u2003\u2003',
  'and': 'and',
};

/// The accents, by the command that represents each, as the combining mark put
/// after the letter it stands over.
const Map<String, String> _accents = {
  "'": '\u0301',
  '`': '\u0300',
  '^': '\u0302',
  '"': '\u0308',
  '~': '\u0303',
  '=': '\u0304',
  '.': '\u0307',
  'c': '\u0327',
  'v': '\u030C',
  'u': '\u0306',
  'H': '\u030B',
  'r': '\u030A',
};

/// The characters a backslash escapes, each showing itself.
const String _escapes = r'%$&#_{}';

bool _letter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

/// A block standing open, and whether it runs on only until the next block
/// begins, as a paragraph does, holds words of its own until something ends
/// it, as an item or a heading does, or holds blocks, as an environment does.
enum _Kind { running, holding, container }

typedef _Block = ({
  String name,
  _Kind kind,
  String? environment,
  int start,
  Map<String, String> said,
  bool marks,
});

/// A brace or a bracket standing open: the character that closes it, the
/// elements it closes, innermost last, what its closing token shows where
/// it closes none, whether it closes the block on top as well, and whether
/// a braced argument straight after it is more of the same element.
final class _Group {
  final int closer;
  final List<String> names;
  final String shown;
  final bool block;
  final bool spread;

  _Group(
    this.closer,
    this.names, {
    this.shown = '',
    this.block = false,
    this.spread = false,
  });
}

/// The one reading of a LaTeX source.
final class _Scan {
  final String source;
  final Limits limits;

  /// What the reading marks, as it marks it.
  final List<_Event> tokens = [];

  /// The elements with markup at neither end, as they close.
  final List<Found> implied = [];

  /// Where the reading stopped at a cap, and why.
  (int, String)? stop;

  /// The container a stretch read on its own stands in, which stands open
  /// before the stretch and after it, and is not read here.
  final String? within;

  /// Whether nothing but [within] stood open at the end of the source,
  /// before the reading closed it.
  bool clean = false;

  /// Whether a verbatim environment ran on to the end of the source, as it
  /// would past the end of a stretch.
  bool _runs = false;

  final List<_Block> blocks = [];
  final List<_Group> groups = [];

  /// Where the last thing read ended, which is where a block closes.
  int content = 0;

  /// Whether the reading is before `\begin{document}`, where nothing but
  /// the title and the author shows.
  bool preamble;

  /// Whether a `\begin{document}` was read, so its end ends the reading.
  bool documented;

  /// The last row read in the table standing open, as the index of its
  /// token, which a rule after it rules below; and the rule read before any
  /// row, which the next row is ruled above by.
  int? _row;
  String? _above;

  /// The cell standing open, as the index of its token, which a
  /// `\multicolumn` spreads across columns.
  int? _cell;

  _Scan(this.source, this.limits, [this.within])
    : preamble = within == null ? _documented(source) : within == 'preamble',
      documented = within == 'document';

  /// The commands defined as words, by name: those defined before the
  /// source, then those it defines.
  Map<String, String> commands = {};

  /// Whether the source defines a command as words, which sets what every
  /// line after it that uses one reads.
  bool defined = false;

  /// Whether what is read now shows nothing: in the preamble, outside every
  /// element but the preamble itself.
  bool get _quiet =>
      preamble &&
      blocks.length == 1 &&
      groups.every((group) => group.names.isEmpty);

  /// Whether the block on top stands in nothing but the document, its
  /// preamble, or the container the stretch read stands in.
  bool get _loose {
    if (blocks.length < 2) {
      return true;
    }
    final below = blocks[blocks.length - 2];
    return below.start < 0 ||
        below.name == 'preamble' ||
        below.name == 'document';
  }

  /// Whether a table's row or cell is what stands open.
  bool get _tabled =>
      blocks.isNotEmpty &&
      (blocks.last.name == 'table' || blocks.last.name == 'td');

  void read() {
    if (within case final name?) {
      blocks.add((
        name: name,
        kind: _Kind.container,
        environment: name == 'document' ? name : null,
        start: -1,
        said: const {},
        marks: false,
      ));
    } else if (preamble) {
      // A block, so the lines between what the preamble holds are space
      // rather than lines of their own.
      _openBlock('preamble', 0, 0, _Kind.container);
    }
    var at = 0;
    while (at < source.length && stop == null) {
      at = _step(at);
    }
    clean =
        groups.isEmpty &&
        blocks.length == (within == null ? 0 : 1) &&
        stop == null &&
        !_runs;
    _closeAll(stop?.$1 ?? source.length);
  }

  /// Whether [source] holds a `\begin{document}` outside a comment.
  static bool _documented(String source) {
    const begun = r'\begin{document}';
    for (
      var at = source.indexOf(begun);
      at >= 0;
      at = source.indexOf(begun, at + 1)
    ) {
      var here = source.lastIndexOf('\n', at) + 1;
      var commented = false;
      while (here < at && !commented) {
        final unit = source.codeUnitAt(here);
        commented = unit == 0x25;
        here += unit == 0x5C ? 2 : 1;
      }
      if (!commented) {
        return true;
      }
    }
    return false;
  }

  /// Reads what stands at [at] and says where the reading goes on from.
  int _step(int at) {
    if ((at == 0 || source.codeUnitAt(at - 1) == 0x0A) && _blank(at)) {
      _break(at);
      // An item no list holds ends at a blank line, as a paragraph does,
      // so the lines after it read as they would alone.
      while (blocks.isNotEmpty && blocks.last.kind == _Kind.holding && _loose) {
        _closeBlock(_settled(at));
      }
      final end = source.indexOf('\n', at);
      return end < 0 ? source.length : end + 1;
    }
    final unit = source.codeUnitAt(at);
    switch (unit) {
      case 0x25: // %
        final end = source.indexOf('\n', at);
        final stop = end < 0 ? source.length : end + 1;
        _mark(_Event(at, stop - at, '#comment', const {}, _Is.comment));
        return stop;
      case 0x5C: // \
        return _command(at);
      case 0x7B: // {
        _syntax(at, 1);
        _push(_Group(0x7D, []), at);
        return at + 1;
      case 0x7D: // }
        return _unbrace(at, 0x7D);
      case 0x5D when groups.isNotEmpty && groups.last.closer == 0x5D: // ]
        return _unbrace(at, 0x5D);
      case 0x26 when _tabled: // &
        return _parted(at);
      case 0x24: // $
        return source.startsWith(r'$$', at)
            ? _display(at, r'$$')
            : _math(at, 1, r'$');
      case 0x7E: // ~
        return _shown(at, 1, '\u00A0');
      case 0x2D when source.startsWith('---', at):
        return _shown(at, 3, '—');
      case 0x2D when source.startsWith('--', at):
        return _shown(at, 2, '–');
      case 0x60: // `
        return source.startsWith('``', at)
            ? _shown(at, 2, '“')
            : _shown(at, 1, '‘');
      case 0x27 when source.startsWith("''", at):
        return _shown(at, 2, '”');
      case 0x20 || 0x09 || 0x0A || 0x0D:
        return at + 1;
    }
    if (_quiet) {
      // Words in the preamble are the arguments of something nothing here
      // reads, and show nothing, a line at a time.
      var stop = at + 1;
      while (stop < source.length && !'\\{}[]\$%~\n'.contains(source[stop])) {
        stop += 1;
      }
      _syntax(at, stop - at);
      return stop;
    }
    _paragraph(at);
    content = at + 1;
    return at + 1;
  }

  /// Whether the line from [at] holds nothing but spaces.
  bool _blank(int at) {
    for (var here = at; here < source.length; here += 1) {
      final unit = source.codeUnitAt(here);
      if (unit == 0x0A) {
        return true;
      }
      if (unit != 0x20 && unit != 0x09 && unit != 0x0D) {
        return false;
      }
    }
    return true;
  }

  // Tokens.

  bool _mark(_Event token) {
    final most = limits.markers;
    if (most != null && tokens.length >= most) {
      stop ??= (token.start, 'more than $most tokens');
      return false;
    }
    tokens.add(token);
    if (token.start + token.length > content) {
      content = token.start + token.length;
    }
    return true;
  }

  /// A token that is syntax showing [said], nothing by default, and
  /// nothing at all in the preamble.
  void _syntax(int start, int length, [String said = '']) {
    _mark(
      _Event(start, length, '#escape', {
        'shows': _quiet ? '' : said,
      }, _Is.shown),
    );
  }

  /// Words represented by a token: in a paragraph, showing [said].
  int _shown(int at, int length, String said) {
    _paragraph(at);
    _syntax(at, length, said);
    return at + length;
  }

  void _open(
    String name,
    int start,
    int length, {
    Map<String, String> attributes = const {},
  }) {
    _mark(_Event(start, length, name, attributes, _Is.open));
  }

  void _close(String name, int start, [int length = 0]) {
    _mark(_Event(start, length, name, const {}, _Is.close));
  }

  bool _deep(int at) {
    final deepest = limits.depth;
    if (deepest == null || blocks.length + groups.length < deepest) {
      return false;
    }
    stop ??= (at, 'blocks nested deeper than $deepest');
    return true;
  }

  void _push(_Group group, int at) {
    if (!_deep(at)) {
      groups.add(group);
    }
  }

  // Blocks.

  void _openBlock(
    String name,
    int start,
    int length,
    _Kind kind, {
    String? environment,
    Map<String, String> attributes = const {},
    bool marks = false,
  }) {
    if (_deep(start)) {
      return;
    }
    // [marks] says this notation represents the block at neither end: nothing
    // stands at its head and nothing closes it, a closing token here being
    // always of no length. Such a block is marked with one range over the
    // whole of it when it closes rather than paired, because a token of no
    // length cannot hold its ground: a character written exactly at one
    // moves it along, so the block's start walked ahead of the caret and
    // what was typed at the head of a paragraph fell outside it.
    if (!marks) {
      _open(name, start, length, attributes: attributes);
    }
    blocks.add((
      name: name,
      kind: kind,
      environment: environment,
      start: start,
      said: attributes,
      marks: marks,
    ));
  }

  void _closeBlock(int at) {
    final held = blocks.removeLast();
    // The container a stretch read on its own stands in is not its to
    // close.
    if (held.start < 0) {
      return;
    }
    if (!held.marks) {
      _close(held.name, at);
      return;
    }
    implied.add((held.start, at, held.name, held.said));
  }

  /// Closes every group standing open at [at], and the heading or term any
  /// of them holds.
  void _closeGroups(int at) {
    while (groups.isNotEmpty) {
      final group = groups.removeLast();
      for (final name in group.names.reversed) {
        _close(name, at);
      }
      if (group.block) {
        blocks.removeLast();
      }
    }
  }

  /// Where what is open closes when a reading at [at] ends it: at the end
  /// of the line the last thing read stands on, or at [at] where that comes
  /// first, so the spaces ending a line belong to the block and typing
  /// there moves nothing.
  int _settled(int at) {
    final end = source.indexOf('\n', content);
    return end < 0 || end > at ? at : end;
  }

  /// Ends the paragraph standing open, as a blank line or a block at [at]
  /// does.
  void _break(int at) {
    final close = _settled(at);
    _closeGroups(close);
    while (blocks.isNotEmpty && blocks.last.kind == _Kind.running) {
      _closeBlock(close);
    }
  }

  /// Ends the paragraph and the item standing open, as an item or a
  /// heading at [at] does.
  void _closeHolding(int at) {
    _break(at);
    final close = _settled(at);
    while (blocks.isNotEmpty && blocks.last.kind != _Kind.container) {
      _closeBlock(close);
    }
  }

  void _closeAll(int at) {
    final close = _settled(at);
    _closeGroups(close);
    while (blocks.isNotEmpty) {
      _closeBlock(close);
    }
  }

  /// Sees that a paragraph stands open for words at [at], opening one where
  /// the block around them holds blocks rather than words.
  void _paragraph(int at) {
    if (blocks.isNotEmpty && blocks.last.name == 'table') {
      _opened(at);
      return;
    }
    if (preamble ||
        (blocks.isNotEmpty && blocks.last.kind != _Kind.container)) {
      return;
    }
    // A paragraph has no markup, only a blank line parting it from the
    // next, so every one is implied.
    _openBlock(
      'p',
      at,
      0,
      _Kind.running,
      marks: true,
      attributes: const {'implied': ''},
    );
  }

  /// A closing brace or bracket at [at]: it closes what its group opened,
  /// and one closing nothing is syntax.
  int _unbrace(int at, int closer) {
    if (groups.isEmpty || groups.last.closer != closer) {
      _syntax(at, 1);
      return at + 1;
    }
    final group = groups.last;
    if (group.spread && _at(at + 1, 0x7B)) {
      // The next argument is more of the same element, apart from the one
      // before it.
      _syntax(at, 2, ' ');
      return at + 2;
    }
    groups.removeLast();
    if (group.names.isEmpty) {
      _syntax(at, 1, group.shown);
    } else {
      // The innermost closes with the brace, the rest after it, so each
      // ends where the one inside it does.
      var here = at;
      var length = 1;
      for (final name in group.names.reversed) {
        _close(name, here, length);
        here += length;
        length = 0;
      }
    }
    if (group.block) {
      blocks.removeLast();
    }
    // A term's description hangs under it until the next item.
    if (group.names.isNotEmpty && group.names.first == 'dt') {
      _openBlock('dd', at + 1, 0, _Kind.holding);
    }
    return at + 1;
  }

  // Commands.

  int _command(int at) {
    if (at + 1 >= source.length) {
      _syntax(at, 1);
      return at + 1;
    }
    final unit = source.codeUnitAt(at + 1);
    if (!_letter(unit)) {
      return _symbol(at, unit);
    }
    var end = at + 1;
    while (end < source.length && _letter(source.codeUnitAt(end))) {
      end += 1;
    }
    final name = source.substring(at + 1, end);
    switch (name) {
      case 'begin':
        return _begin(at, end);
      case 'end':
        return _end(at, end);
      case 'item':
        return _item(at, end);
      case 'bibitem':
        return _entry(at, end);
      case 'bibinfo' || 'bibfield' when _at(end, 0x7B):
        return _field(at, end);
      case 'verb':
        return _verb(at, end);
      case 'tikz':
        return _tikz(at, end);
      case 'url':
        return _url(at, end);
      case 'email':
        return _url(at, end, 'mailto:');
      case 'label':
        // An anchor where it stands, named by its key.
        final stop = _at(end, 0x7B) ? _matched(end, 0x7D) : -1;
        if (stop < 0) {
          _syntax(at, end - at);
          return end;
        }
        _open(
          'a',
          at,
          stop - at,
          attributes: {'id': source.substring(end + 1, stop - 1).trim()},
        );
        _close('a', stop);
        return stop;
      case 'ref' || 'pageref' || 'autoref' || 'eqref':
        // A link to the anchor its key names, showing the key, and saying it
        // is a reference, which a sheet shows by what it refers to; one to an
        // equation says that too, since LaTeX puts its number in brackets.
        final stop = _at(end, 0x7B) ? _matched(end, 0x7D) : -1;
        if (stop < 0) {
          _syntax(at, end - at);
          return end;
        }
        _paragraph(at);
        _open(
          'a',
          at,
          end + 1 - at,
          attributes: {
            'href': '#${source.substring(end + 1, stop - 1).trim()}',
            'class': name == 'eqref' ? 'ref eqref' : 'ref',
          },
        );
        _push(_Group(0x7D, ['a']), at);
        return end + 1;
      case 'href':
        return _href(at, end);
      case 'par':
        _break(at);
        _syntax(at, end - at);
        return end;
      case 'newline':
        _paragraph(at);
        _open('br', at, end - at);
        return end;
      case 'iffalse':
        // What stands between it and its \fi is never read, the
        // conditionals inside nesting.
        final stop = _unread(end);
        _mark(_Event(at, stop - at, '#comment', const {}, _Is.comment));
        return stop;
      case 'def' || 'gdef' || 'edef' || 'xdef':
        final stop = _defined(end);
        _syntax(at, stop - at);
        return stop;
      case 'multicolumn' when _tabled:
        return _spanned(at, end);
      case 'cmidrule' when _tabled:
        // A rule under some columns only, which a row cannot ask for.
        var stop = _options(end);
        if (_at(stop, 0x28)) {
          final close = source.indexOf(')', stop);
          stop = close < 0 ? stop : close + 1;
        }
        stop = _arguments(stop);
        _syntax(at, stop - at);
        return stop;
    }
    if (_rules[name] case final weight? when _tabled) {
      return _ruled(at, end, weight);
    }
    if (_headings[name] case final held?) {
      return _heading(at, end, held);
    }
    if (_wrapping[name] case final held? when _at(end, 0x7B)) {
      _paragraph(at);
      _open(held, at, end + 1 - at);
      _push(_Group(0x7D, [held]), at);
      return end + 1;
    }
    if (_matter[name] case (final held, final attributes)) {
      final stop = _options(_starred(end));
      if (_at(stop, 0x7B)) {
        _paragraph(at);
        _open(held, at, stop + 1 - at, attributes: attributes);
        _push(_Group(0x7D, [held]), at);
        return stop + 1;
      }
    }
    if (_keyed[name] case (final left, final right)) {
      final stop = _options(_starred(end));
      if (_at(stop, 0x7B)) {
        _paragraph(at);
        _syntax(at, stop + 1 - at, left);
        _push(_Group(0x7D, [], shown: right), at);
        return stop + 1;
      }
    }
    if (_declarations[name] case final held?
        when groups.isNotEmpty &&
            groups.last.closer == 0x7D &&
            groups.last.shown.isEmpty) {
      // TeX passes over the spaces after a control word, and a declaration
      // stands before the words it sets, so its token takes them.
      var stop = end;
      while (_at(stop, 0x20) || _at(stop, 0x09)) {
        stop += 1;
      }
      _paragraph(at);
      _open(held, at, stop - at);
      groups.last.names.add(held);
      return stop;
    }
    if (_symbols[name] case final held?) {
      return _shown(at, end - at, held);
    }
    if (_accents[name] case final mark? when _at(end, 0x7B)) {
      return _accent(at, end, mark);
    }
    if (name == 'includegraphics') {
      // A picture: an img over the whole command, saying its file.
      final open = _options(_starred(end));
      final stop = _at(open, 0x7B) ? _matched(open, 0x7D) : -1;
      if (stop < 0) {
        _syntax(at, open - at);
        return open;
      }
      _paragraph(at);
      _open(
        'img',
        at,
        stop - at,
        attributes: {'src': source.substring(open + 1, stop - 1).trim()},
      );
      return stop;
    }
    if (_silent.contains(name)) {
      // A definition may name what it defines outside braces:
      // `\providecommand\name[2]{...}`.
      var from = _starred(end);
      if (_at(from, 0x5C)) {
        from = _named(from);
      }
      final stop = _arguments(from);
      if (_commanding.contains(name)) {
        if (_worded(source.substring(end, stop)) case (
          final called,
          final words,
        )) {
          commands = {...commands, called: words};
          defined = true;
          _mark(
            _Event(at, stop - at, '#escape', {
              'shows': '',
              'command': called,
              'value': words,
            }, _Is.shown),
          );
          return stop;
        }
      }
      _syntax(at, stop - at);
      return stop;
    }
    if (commands[name] case final words?) {
      // A command defined as words shows them, and takes the spaces after
      // it, as TeX passes over them.
      var stop = end;
      while (_at(stop, 0x20) || _at(stop, 0x09)) {
        stop += 1;
      }
      return _shown(at, stop - at, words);
    }
    // A command nothing here knows is an element of its own name over its
    // braced arguments, so a sheet can style it; its options show nothing,
    // and one with no argument is syntax.
    final stop = _options(_starred(end));
    if (_at(stop, 0x7B)) {
      _paragraph(at);
      _open(name, at, stop + 1 - at);
      _push(_Group(0x7D, [name], spread: true), at);
      return stop + 1;
    }
    _syntax(at, stop - at);
    return stop;
  }

  /// Past the `\fi` ending a conditional whose test ends at [end], every
  /// `\if` between opening one more that a `\fi` closes; or the end.
  int _unread(int end) {
    var depth = 1;
    var at = end;
    while (at < source.length) {
      final found = source.indexOf(r'\', at);
      if (found < 0) {
        break;
      }
      final stop = _named(found);
      final name = source.substring(found + 1, stop);
      if (name == 'fi') {
        depth -= 1;
        if (depth == 0) {
          return stop;
        }
      } else if (name.startsWith('if')) {
        depth += 1;
      }
      at = stop;
    }
    _runs = true;
    return source.length;
  }

  /// The name and the words of a definition whose arguments are [said],
  /// `{\name}{words}` or `\name{words}`: or null where it takes arguments
  /// or its body is more than words.
  static (String, String)? _worded(String said) {
    final match = _wording.firstMatch(said);
    return match == null ? null : (match[1] ?? match[2]!, match[3]!);
  }

  /// A definition with no arguments whose body is words alone.
  static final _wording = RegExp(
    r'^\*?\s*(?:\{\s*\\([A-Za-z]+)\s*\}|\\([A-Za-z]+))\s*\{([^\\{}#$%]*)\}$',
  );

  /// Past a definition from [end]: the name it defines, its parameters and
  /// its braced body.
  int _defined(int end) {
    var at = end;
    while (_at(at, 0x20)) {
      at += 1;
    }
    if (_at(at, 0x5C)) {
      at = _named(at);
    }
    while (at < source.length && !_at(at, 0x7B) && !_at(at, 0x0A)) {
      at += 1;
    }
    final stop = _at(at, 0x7B) ? _matched(at, 0x7D) : -1;
    return stop < 0 ? end : stop;
  }

  /// Past the control sequence at [at]: a backslash and its letters, or
  /// the one character after it.
  int _named(int at) {
    var here = at + 1;
    if (here < source.length && _letter(source.codeUnitAt(here))) {
      while (here < source.length && _letter(source.codeUnitAt(here))) {
        here += 1;
      }
      return here;
    }
    return here < source.length ? here + 1 : here;
  }

  /// `\bibitem[label]{key}`: an entry of a bibliography, holding the words
  /// after it until the next, and carrying its key as its identity. The
  /// label and the key are the token's, since what a reader sees of an
  /// entry is its words; a comment may stand between the two, as a
  /// generated bibliography writes one.
  int _entry(int at, int end) {
    _closeHolding(at);
    var stop = _options(end);
    var key = '';
    var here = stop;
    while (here < source.length) {
      if (_at(here, 0x25)) {
        final line = source.indexOf('\n', here);
        here = line < 0 ? source.length : line + 1;
      } else if (_at(here, 0x20) || _at(here, 0x09) || _at(here, 0x0A)) {
        here += 1;
      } else {
        break;
      }
    }
    if (_at(here, 0x7B)) {
      final close = _matched(here, 0x7D);
      if (close > 0) {
        key = source.substring(here + 1, close - 1);
        stop = close;
      }
    }
    _openBlock(
      'li',
      at,
      stop - at,
      _Kind.holding,
      attributes: {if (key.isNotEmpty) 'id': key},
    );
    return stop;
  }

  /// `\bibinfo{field}{words}` and `\bibfield{field}{words}`: the words of
  /// one field of an entry, carrying the field's name, which is syntax.
  int _field(int at, int end) {
    final named = _matched(end, 0x7D);
    if (named < 0 || !_at(named, 0x7B)) {
      _syntax(at, end - at);
      return end;
    }
    _paragraph(at);
    final name = source.substring(at + 1, end);
    _open(
      name,
      at,
      named + 1 - at,
      attributes: {'field': source.substring(end + 1, named - 1)},
    );
    _push(_Group(0x7D, [name]), at);
    return named + 1;
  }

  // Tables.

  /// Opens a row at [at], and its first cell, ruled above where a rule was
  /// read before it.
  void _opened(int at) {
    final above = _above;
    _above = null;
    _row = tokens.length;
    _openBlock('tr', at, 0, _Kind.holding, attributes: {'above': ?above});
    _cell = tokens.length;
    _openBlock('td', at, 0, _Kind.holding);
  }

  /// `&` at [at]: the cell standing open closes with it, and the next opens
  /// after it.
  int _parted(int at) {
    _closeGroups(at);
    if (blocks.last.name == 'table') {
      _opened(at);
    }
    blocks.removeLast();
    _close('td', at, 1);
    _cell = tokens.length;
    _openBlock('td', at + 1, 0, _Kind.holding);
    return at + 1;
  }

  /// `\\` at [at] in a table, through its options at [stop]: the row
  /// standing open closes with it.
  int _ended(int at, int stop) {
    _closeGroups(at);
    if (blocks.last.name == 'table') {
      _syntax(at, stop - at);
      return stop;
    }
    _closeBlock(at);
    blocks.removeLast();
    _close('tr', at, stop - at);
    _cell = null;
    return stop;
  }

  /// A rule between rows: the row before it asks for it below itself, and
  /// where there is none yet, the row after it above.
  int _ruled(int at, int end, String weight) {
    final stop = _options(end);
    final row = _row;
    if (row != null && blocks.last.name == 'table') {
      _said(row, 'below', weight);
    } else {
      _above = weight;
    }
    _syntax(at, stop - at);
    return stop;
  }

  /// `\multicolumn{count}{columns}{words}`: the cell it stands in spreads
  /// across that many columns, and the words are the cell's.
  int _spanned(int at, int end) {
    final count = _at(end, 0x7B) ? _matched(end, 0x7D) : -1;
    final columns = count < 0 ? -1 : _matched(count, 0x7D);
    if (columns < 0 || !_at(columns, 0x7B)) {
      _syntax(at, end - at);
      return end;
    }
    _paragraph(at);
    final wide = int.tryParse(source.substring(end + 1, count - 1).trim());
    if (wide != null && _cell != null) {
      _said(_cell!, 'colspan', '$wide');
    }
    _syntax(at, columns + 1 - at);
    _push(_Group(0x7D, []), at);
    return columns + 1;
  }

  /// Gives the token at [index] the attribute [name] saying [value].
  void _said(int index, String name, String value) {
    if (index < tokens.length) {
      tokens[index] = tokens[index].adding(name, value);
    }
  }

  /// A backslash and the one character after it that is not a letter.
  int _symbol(int at, int unit) {
    switch (unit) {
      case 0x5C: // \\
        final stop = _options(_starred(at + 2));
        if (_tabled) {
          return _ended(at, stop);
        }
        _paragraph(at);
        _open('br', at, stop - at);
        return stop;
      case 0x28: // \(
        return _math(at, 2, r'\)');
      case 0x5B: // \[
        return _display(at, r'\]');
    }
    final said = String.fromCharCode(unit);
    if (_escapes.contains(said)) {
      return _shown(at, 2, said);
    }
    if (_accents[said] case final mark?) {
      return _accent(at, at + 2, mark);
    }
    return switch (unit) {
      0x20 || 0x0A || 0x09 => _shown(at, 2, ' '),
      0x2C => _shown(at, 2, '\u2009'), // \,
      _ => _shown(at, 2, ''),
    };
  }

  /// An accent over the letter after it, or over the one in braces, shown
  /// as the letter and the mark; over nothing, the accent itself.
  int _accent(int at, int end, String mark) {
    final symbol = !_letter(source.codeUnitAt(at + 1));
    if (_at(end, 0x7B)) {
      if (_at(end + 1, 0x7D)) {
        return _shown(at, end + 2 - at, symbol ? source[at + 1] : '');
      }
      if (end + 2 < source.length &&
          _at(end + 2, 0x7D) &&
          !r'\{'.contains(source[end + 1])) {
        return _shown(at, end + 3 - at, '${source[end + 1]}$mark');
      }
    } else if (symbol &&
        end < source.length &&
        _letter(source.codeUnitAt(end))) {
      return _shown(at, end + 1 - at, '${source[end]}$mark');
    }
    return _shown(at, end - at, '');
  }

  /// A heading, a title or an author: a block whose words are its braced
  /// argument.
  int _heading(int at, int end, String name) {
    final start = _options(_starred(end));
    if (!_at(start, 0x7B)) {
      _syntax(at, start - at);
      return start;
    }
    _closeHolding(at);
    _openBlock(name, at, start + 1 - at, _Kind.holding);
    _push(_Group(0x7D, [name], block: true), at);
    return start + 1;
  }

  /// An item: a term in a description, else an item holding the words
  /// after it until the next.
  int _item(int at, int end) {
    _closeHolding(at);
    final described = blocks.isNotEmpty && blocks.last.name == 'dl';
    if (described && _at(end, 0x5B)) {
      _openBlock('dt', at, end + 1 - at, _Kind.holding);
      _push(_Group(0x5D, ['dt'], block: true), at);
      return end + 1;
    }
    final stop = _options(end);
    _openBlock(described ? 'dd' : 'li', at, stop - at, _Kind.holding);
    return stop;
  }

  /// The name an environment's braces hold at [end], and where it closes,
  /// or null where there is no such name.
  (String, int)? _environment(int end) {
    if (!_at(end, 0x7B)) {
      return null;
    }
    for (var at = end + 1; at < source.length; at += 1) {
      final unit = source.codeUnitAt(at);
      if (unit == 0x7D) {
        return at == end + 1 ? null : (source.substring(end + 1, at), at + 1);
      }
      if (unit == 0x0A || unit == 0x5C || unit == 0x7B) {
        return null;
      }
    }
    return null;
  }

  int _begin(int at, int end) {
    final named = _environment(end);
    if (named == null) {
      _syntax(at, end - at);
      return end;
    }
    final (name, close) = named;
    if (name == 'document' && preamble) {
      // The preamble runs to the document, blank lines and all, so nothing
      // stands between the two blocks.
      _closeGroups(at);
      while (blocks.isNotEmpty) {
        _closeBlock(at);
      }
      preamble = false;
      documented = true;
      _openBlock(
        'document',
        at,
        close - at,
        _Kind.container,
        environment: name,
      );
      return close;
    }
    final stop = _arguments(close);
    if (_commented.contains(name)) {
      // All of it, to its own end, is one comment.
      final closing = '\\end{$name}';
      final found = source.indexOf(closing, stop);
      if (found < 0) {
        _runs = true;
      }
      final end = found < 0 ? source.length : found + closing.length;
      _mark(_Event(at, end - at, '#comment', const {}, _Is.comment));
      return end;
    }
    _break(at);
    if (_verbatim[name] case final held?) {
      // The words stand as they are to the environment's own end.
      final closing = '\\end{$name}';
      final found = source.indexOf(closing, stop);
      // A display says which environment it is, so a sheet numbers the ones
      // LaTeX numbers, and the first label written inside it, which its
      // body keeps as source, so a reference can reach it.
      final label = held == 'equation'
          ? RegExp(r'\\label\{([^}]*)\}')
                .firstMatch(source.substring(stop, found < 0 ? null : found))
                ?.group(1)
                ?.trim()
          : null;
      _open(
        held,
        at,
        stop - at,
        attributes: {if (held == 'equation') 'env': name, 'label': ?label},
      );
      if (found < 0) {
        _runs = true;
        _close(held, source.length);
        return source.length;
      }
      _close(held, found, closing.length);
      return found + closing.length;
    }
    final element = _environments[name];
    if (element == 'table') {
      _row = null;
      _above = null;
    }
    _openBlock(
      element ?? 'div',
      at,
      stop - at,
      _Kind.container,
      environment: name,
      attributes: {
        if (element == null || name == 'thebibliography') 'class': name,
      },
    );
    return stop;
  }

  int _end(int at, int end) {
    final named = _environment(end);
    if (named == null) {
      _syntax(at, end - at);
      return end;
    }
    final (name, stop) = named;
    _break(at);
    for (var index = blocks.length - 1; index >= 0; index -= 1) {
      if (blocks[index].environment == name) {
        while (blocks.length > index + 1) {
          _closeBlock(_settled(at));
        }
        // Nothing after the document's end is read by TeX, nor here: it is
        // the end's own token, so nothing stands after the document.
        final ending = name == 'document' && documented;
        _close(
          blocks.removeLast().name,
          at,
          (ending ? source.length : stop) - at,
        );
        if (ending) {
          _closeAll(source.length);
          return source.length;
        }
        return stop;
      }
    }
    _syntax(at, stop - at);
    return stop;
  }

  /// `\verb|words|`, whose words stand as they are between a character and
  /// its next appearance on the line.
  int _verb(int at, int end) {
    final start = _starred(end);
    if (start < source.length &&
        !_letter(source.codeUnitAt(start)) &&
        !' \n'.contains(source[start])) {
      final delimiter = source.codeUnitAt(start);
      for (var found = start + 1; found < source.length; found += 1) {
        final unit = source.codeUnitAt(found);
        if (unit == 0x0A) {
          break;
        }
        if (unit == delimiter) {
          _paragraph(at);
          _open('code', at, start + 1 - at);
          _close('code', found, 1);
          return found + 1;
        }
      }
    }
    _syntax(at, start - at);
    return start;
  }

  /// `\url{address}`: a link whose words are its address.
  int _url(int at, int end, [String prefix = '']) {
    final close = _at(end, 0x7B) ? _address(end + 1) : -1;
    if (close < 0) {
      _syntax(at, end - at);
      return end;
    }
    _paragraph(at);
    _open(
      'a',
      at,
      end + 1 - at,
      attributes: {'href': '$prefix${_unescaped(end + 1, close)}'},
    );
    _close('a', close, 1);
    return close + 1;
  }

  /// `\href{address}{words}`: a link whose token carries the address.
  int _href(int at, int end) {
    final close = _at(end, 0x7B) ? _address(end + 1) : -1;
    if (close < 0 || !_at(close + 1, 0x7B)) {
      _syntax(at, end - at);
      return end;
    }
    _paragraph(at);
    _open(
      'a',
      at,
      close + 2 - at,
      attributes: {'href': _unescaped(end + 1, close)},
    );
    _push(_Group(0x7D, ['a']), at);
    return close + 2;
  }

  /// Where the address from [from] closes, on its own line, or -1.
  int _address(int from) {
    for (var at = from; at < source.length; at += 1) {
      final unit = source.codeUnitAt(at);
      if (unit == 0x7D) {
        return at;
      }
      if (unit == 0x0A || unit == 0x7B) {
        return -1;
      }
      if (unit == 0x5C) {
        at += 1;
      }
    }
    return -1;
  }

  /// The address between [from] and [to] with its escapes read.
  String _unescaped(int from, int to) => source
      .substring(from, to)
      .replaceAllMapped(RegExp(r'\\([#%&_~$])'), (match) => match[1]!);

  /// Inline mathematics from [at], opened by [length] characters and closed
  /// by [closer]: its words are TeX, read by the formula setter as they
  /// stand. Unclosed, the opening is syntax.
  int _math(int at, int length, String closer) {
    _paragraph(at);
    final found = _closing(at + length, closer);
    if (found < 0) {
      _syntax(at, length);
      return at + length;
    }
    _open('math', at, length);
    _close('math', found, closer.length);
    return found + closer.length;
  }

  /// Displayed mathematics, which stands as a block of its own.
  int _display(int at, String closer) {
    final found = _closing(at + 2, closer);
    if (found < 0) {
      return _shown(at, 2, '');
    }
    _break(at);
    _open('equation', at, 2);
    _close('equation', found, closer.length);
    return found + closer.length;
  }

  /// Where [closer] stands from [from], passing over what a backslash
  /// escapes, or -1 where a blank line or the end comes first.
  int _closing(int from, String closer) {
    if (_unclosed[closer] case (final low, final high)
        when low <= from && from < high) {
      return -1;
    }
    var at = from;
    while (at < source.length) {
      if (source.startsWith(closer, at)) {
        return at;
      }
      final unit = source.codeUnitAt(at);
      if (unit == 0x0A && at + 1 < source.length && _blank(at + 1)) {
        break;
      }
      at += _escaping(at) ? 2 : 1;
    }
    _unclosed[closer] = (from, at);
    return -1;
  }

  /// For each closer, a stretch it was looked for in and not found, so a
  /// paragraph of openers that never close is looked through once.
  final _unclosed = <String, (int, int)>{};

  /// For each closing bracket, a stretch it was looked for in and not
  /// found, with no brace in it, so that from anywhere in it the search
  /// fails the same way.
  final _unmatched = <int, (int, int)>{};

  /// Whether a backslash at [at] escapes what follows it, which a line
  /// end it is not, since a blank line after one still ends a paragraph.
  bool _escaping(int at) => _at(at, 0x5C) && !_at(at + 1, 0x0A);

  bool _at(int at, int unit) =>
      at < source.length && source.codeUnitAt(at) == unit;

  int _starred(int at) => _at(at, 0x2A) ? at + 1 : at;

  /// Past the bracketed options standing at [at].
  int _options(int at) {
    var here = at;
    while (_at(here, 0x5B)) {
      final stop = _matched(here, 0x5D);
      if (stop < 0) {
        break;
      }
      here = stop;
    }
    return here;
  }

  /// Past the bracketed and braced arguments standing at [at].
  int _arguments(int at) {
    var here = at;
    while (_at(here, 0x5B) || _at(here, 0x7B)) {
      final stop = _matched(
        here,
        source.codeUnitAt(here) == 0x5B ? 0x5D : 0x7D,
      );
      if (stop < 0) {
        break;
      }
      here = stop;
    }
    return here;
  }

  /// An inline TikZ picture: its options, then a braced body or one
  /// statement to its semicolon, standing as it is under one element over
  /// the whole, for a reader of TikZ to draw.
  int _tikz(int at, int end) {
    var stop = _options(end);
    while (_at(stop, 0x20) || _at(stop, 0x09)) {
      stop += 1;
    }
    final close = _at(stop, 0x7B)
        ? _matched(stop, 0x7D)
        : _matched(stop - 1, 0x3B);
    if (close < 0) {
      _syntax(at, end - at);
      return end;
    }
    _paragraph(at);
    _open('tikz', at, end - at);
    _close('tikz', close);
    return close;
  }

  /// Past the [closer] matching the bracket or brace at [at], braces
  /// nesting inside, or -1 where a blank line or the end comes first.
  int _matched(int at, int closer) {
    if (_unmatched[closer] case (final low, final high)
        when low <= at && at < high) {
      return -1;
    }
    var depth = 0;
    var braced = false;
    var here = at + 1;
    while (here < source.length) {
      final unit = source.codeUnitAt(here);
      if (unit == closer && depth == 0) {
        return here + 1;
      }
      if (unit == 0x7B) {
        depth += 1;
        braced = true;
      } else if (unit == 0x7D) {
        depth -= 1;
        if (depth < 0) {
          return -1;
        }
      } else if (unit == 0x0A && here + 1 < source.length && _blank(here + 1)) {
        break;
      }
      here += _escaping(here) ? 2 : 1;
    }
    if (!braced) {
      _unmatched[closer] = (at, here);
    }
    return -1;
  }
}
