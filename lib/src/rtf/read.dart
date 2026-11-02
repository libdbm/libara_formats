/// RTF's groups read over its tokens: which text is hidden, at layer 2, and
/// the elements, at layer 3.
library;

import 'package:libara/libara.dart';

import '../import/assemble.dart';
import '../import/styles.dart';
import '../lexing.dart';

/// The destinations whose text is not the document's: the header's tables,
/// a picture's data, the numbers a list item shows, a field's instruction,
/// headers and footers. Every `{\*...}` group is one as well.
const Set<String> _hidden = {
  'fonttbl',
  'colortbl',
  'stylesheet',
  'info',
  'listtable',
  'listoverridetable',
  'revtbl',
  'pict',
  'listtext',
  'pntext',
  'pntxta',
  'pntxtb',
  'fldinst',
  'header',
  'headerl',
  'headerr',
  'headerf',
  'footer',
  'footerl',
  'footerr',
  'footerf',
  'filetbl',
  'object',
  'nonshppict',
  'docvar',
  'pgdsctbl',
  'mmathPr',
  'xmlnstbl',
  'rsidtbl',
  'generator',
  'NeXTGraphic',
};

/// The destinations whose text is the document's, though it does not stand
/// in the paragraph around it as its own: a footnote, and a field.
const Set<String> _apart = {'footnote', 'field', 'fldrslt'};

/// The hidden destinations that stand within a paragraph, and so are read
/// with what holds them rather than as elements of their own.
const Set<String> _inline = {'listtext', 'pntext', 'pict', 'NeXTGraphic'};

/// What each token is in: whether its text is hidden, and how many
/// destinations hold it.
typedef _Place = ({bool hidden, int apart});

/// For each of [names], the tokens of a document in order, whether it
/// stands within a hidden destination and how many destinations hold it;
/// with [braces], where each group opens, the destination its first word
/// makes it, if any.
List<_Place> _placed(List<String> names, [Map<int, String>? braces]) {
  final places = <_Place>[];
  final open = <_Place>[];
  var place = (hidden: false, apart: 0);
  for (var index = 0; index < names.length; index++) {
    final name = names[index];
    if (name == '{') {
      open.add(place);
      // The word after the brace, after a `\*` where there is one, says
      // what the group is.
      var next = index + 1;
      final starred = next < names.length && names[next] == r'#symbol*';
      if (starred) {
        next++;
      }
      final word = next < names.length ? names[next] : '';
      // A footnote or field is the document's text, starred or not, as
      // LibreOffice writes a footnote.
      if (!_apart.contains(word) && (starred || _hidden.contains(word))) {
        place = (hidden: true, apart: place.apart + 1);
        braces?[index] = word;
      } else if (_apart.contains(word)) {
        place = (hidden: place.hidden, apart: place.apart + 1);
        braces?[index] = word;
      }
      places.add(place);
    } else if (name == '}') {
      places.add(place);
      if (open.isNotEmpty) {
        place = open.removeLast();
      }
    } else {
      places.add(place);
    }
  }
  return places;
}

/// What the scanner names [token], with a control symbol's symbol, so
/// that `\*` is told from the rest.
String _named(ARange token) {
  final name = '${token.get('')}';
  return name == '#symbol' ? '#symbol${token.get('symbol')}' : name;
}

/// [tokens], as the scanner read the whole text, with what stands within a
/// hidden destination showing nothing: its runs of text are `#hidden`, and
/// nothing in it says `shows`.
List<ARange> hidden(List<ARange> tokens) {
  final places = _placed([for (final token in tokens) _named(token)]);
  return [
    for (final (index, token) in tokens.indexed)
      if (!places[index].hidden)
        token
      else if ('${token.get('')}' == prose)
        ARange.from(token, {'': literal('#hidden')})
      else if (token.get('shows') != null)
        ARange.from(token, {
          for (final MapEntry(:key, :value) in token.attributes.entries)
            if (key != 'shows') key: value,
        })
      else
        token,
  ];
}

/// A paragraph style: its name, the size its characters are, in half
/// points, where it says one, and the faces it sets.
typedef _Style = ({String name, int? size, Set<String> faces});

/// The fonts read as monospaced, by name in lower case with its spaces
/// taken away: a name beginning with one of these, such as Cocoa's
/// `CourierNewPSMT` or `Menlo-Regular`, is one.
const _monospaced = [
  'couriernew',
  'courier',
  'menlo',
  'monaco',
  'sfmono',
  'andalemono',
  'consolas',
  'lucidaconsole',
];

/// The words that turn a face on, each with the face; a parameter of 0
/// turns it off.
const Map<String, String> _faces = {
  'b': 'strong',
  'i': 'em',
  'strike': 's',
  'super': 'sup',
  'sub': 'sub',
  'ul': 'u',
  'uld': 'u',
  'uldash': 'u',
  'uldashd': 'u',
  'uldashdd': 'u',
  'uldb': 'u',
  'ulhwave': 'u',
  'ulldash': 'u',
  'ulth': 'u',
  'ulthd': 'u',
  'ulthdash': 'u',
  'ulw': 'u',
  'ulwave': 'u',
  // Revisions are properties of a run, as faces are.
  'revised': 'ins',
  'deleted': 'del',
  'crauth': 'format',
};

/// The words that say who made a revision and when, by the element it is:
/// a deletion's are its own, and an insertion's serve where they are not.
const Map<String, (List<String>, List<String>)> _revisions = {
  'ins': (['revauth'], ['revdttm']),
  'del': (['revauthdel', 'revauth'], ['revdttmdel', 'revdttm']),
  'format': (['crauth'], ['crdate']),
};

/// The words that turn faces off.
const Map<String, List<String>> _offs = {
  'ulnone': ['u'],
  'nosupersub': ['sup', 'sub'],
  'plain': [
    'strong',
    'em',
    'u',
    's',
    'sup',
    'sub',
    'code',
    'ins',
    'del',
    'format',
  ],
};

/// [document]'s elements over the tokens of [region], as the layer above
/// sees them: each destination directly within the document group, under
/// its word, and each paragraph.
Derived elements(Layered<int> document, Range region) {
  final tokens = [for (final (_, token) in document.span(2, region)) token];
  final names = [for (final token in tokens) _named(token)];
  int? value(int index) => int.tryParse('${tokens[index].get('value') ?? ''}');
  String text(int index) => String.fromCharCodes(
    document.items.slice(tokens[index].start, tokens[index].length).items,
  );
  final braces = <int, String>{};
  final places = _placed(names, braces);
  // How many tokens before each show something.
  final counted = <int>[0];
  for (final (index, token) in tokens.indexed) {
    final visible =
        !places[index].hidden &&
        (names[index] == prose || token.get('shows') != null);
    counted.add(counted.last + (visible ? 1 : 0));
  }
  bool shows(int from, int to) => counted[to + 1] > counted[from];
  final ranges = <ARange>[];
  final closes = _closes(names);
  // The destinations directly within the document group.
  final styles = <int, _Style>{};
  final monospaced = <int>{};
  // Each list's kinds, by level, and the list each override names.
  final lists = <int, List<String>>{};
  final overrides = <int, int>{};
  final authors = <String>[];
  var depth = 0;
  for (var index = 0; index < names.length; index++) {
    if (names[index] == '{') {
      depth++;
      if (braces[index] case final word?
          when depth == 2 && places[index].hidden && !_inline.contains(word)) {
        final close = closes[index] ?? names.length - 1;
        ranges.add(_range(index, close - index + 1, {'': word}));
        if (word == 'stylesheet') {
          styles.addAll(_styles(tokens, names, text, index, close));
        }
        if (word == 'fonttbl') {
          monospaced.addAll(_fonts(tokens, names, text, index, close));
        }
        if (word == 'listtable') {
          lists.addAll(_lists(tokens, names, text, index, close));
        }
        if (word == 'revtbl') {
          authors.addAll(_authors(names, text, index, close));
        }
        if (word == 'listoverridetable') {
          overrides.addAll(_overrides(tokens, names, index, close));
        }
      }
    } else if (names[index] == '}') {
      depth--;
    }
  }
  // The body size: the default style's where it says one, and otherwise
  // what most characters are, the smaller where two tie.
  final sizes = <int, int>{};
  // The paragraphs, each from the token after the last paragraph mark to
  // its own, with the size of each character it holds.
  var size = 24;
  final open = <int>[];
  var start = _body(names, places, braces);
  var style = 0;
  int? level;
  int? item;
  var tier = 0;
  final problems = <ARange>[];
  final held = <int>[];
  // The table being read: the row open, where its open cell starts, and
  // the rows read since the last paragraph.
  int? row;
  var cell = 0;
  // Whether the row open is a header row, as `\trhdr` says.
  var header = false;
  final rows = <(int, int)>[];
  // Where the table's first row stands among the ranges: the table goes
  // before it, so that a table of one row holds the row, not the reverse.
  var first = 0;
  void table() {
    if (rows.isNotEmpty) {
      final from = rows.first.$1;
      ranges.insert(
        first,
        _range(from, rows.last.$2 - from + 1, {'': 'table'}),
      );
      rows.clear();
    }
  }

  // The faces on, each from the token that turned it on, and whether the
  // paragraph's style sets it, which makes it the style's and no face of
  // its own; and those of each group around.
  final faces = <String, (int, bool)>{};
  final saved = <Map<String, (int, bool)>>[];
  // Who made the revision [face] from [from] to [end], and when, from the
  // words within it; and for a change of formatting, what it was before.
  Map<String, String?> revision(String face, int from, int end) {
    final (authored, dated) = _revisions[face]!;
    int? find(List<String> words) {
      for (final word in words) {
        for (var at = from; at <= end; at++) {
          if (names[at] == word) {
            return value(at);
          }
        }
      }
      return null;
    }

    final author = find(authored);
    if (author != null && author >= authors.length) {
      problems.add(
        _range(from, end - from + 1, {
          'message': 'the revision names author $author, past the table',
        }),
      );
    }
    final date = find(dated);
    return {
      'author': author == null || author >= authors.length
          ? null
          : authors[author],
      'date': date == null ? null : _dated(date),
      if (face == 'format')
        'was': [
          for (var at = from; at <= end; at++)
            if (braces[at] == 'oldcprops')
              for (var inner = at + 2; inner < (closes[at] ?? at); inner++)
                if (!names[inner].startsWith('#') &&
                    !const {
                      'crauth',
                      'crdate',
                      'oldcprops',
                    }.contains(names[inner]))
                  '\\${names[inner]}${value(inner) ?? ''}',
        ].join(),
    };
  }

  // A face over nothing that shows, such as a footnote's superscript
  // mark, is none.
  void close(String face, int end) {
    if (faces.remove(face) case (final from, final styled)
        when !styled && shows(from, end)) {
      ranges.add(
        _range(from, end - from + 1, {
          '': face,
          ...?_revisions[face] == null ? null : revision(face, from, end),
        }),
      );
    }
  }

  void turn(String face, int at) {
    if (!faces.containsKey(face)) {
      final styled = styles[style]?.faces.contains(face) ?? false;
      faces[face] = (at, styled);
    }
  }

  void paragraph(int end) {
    if (end < start) {
      return;
    }
    final found = styles[style];
    final named = styled(
      found?.name ?? '',
      level: level == null ? null : level + 1,
    );
    // A paragraph of a list is an item, of the kind its list's level says.
    final kinds = lists[overrides[item]];
    if (item != null && kinds == null) {
      problems.add(
        _range(start, end - start + 1, {
          'message': 'the list \\ls$item names is not defined',
        }),
      );
    }
    final kind = kinds == null ? null : kinds[tier.clamp(0, kinds.length - 1)];
    ranges.add(
      _range(start, end - start + 1, {
        '': kind == null ? named.name : 'li',
        'class': ?found?.name,
        'size': ?_uniform(held),
        'list': ?kind,
        'level': ?kind == null ? null : '${tier + 1}',
        'id': ?kind == null ? null : '$item',
      }),
    );
    held.clear();
  }

  for (var index = start; index < names.length; index++) {
    final name = names[index];
    final place = places[index];
    if (name == '{') {
      open.add(size);
      saved.add(Map.of(faces));
      continue;
    }
    if (name == '}') {
      if (open.isNotEmpty) {
        size = open.removeLast();
      }
      if (saved.isNotEmpty) {
        // What the group turned on closes with it; what it turned off is
        // on again past it.
        final restored = saved.removeLast();
        for (final face in [...faces.keys]) {
          if (restored[face] != faces[face]) {
            close(face, index);
          }
        }
        for (final MapEntry(key: face, value: (_, styled))
            in restored.entries) {
          if (!faces.containsKey(face)) {
            faces[face] = (index, styled);
          }
        }
      }
      continue;
    }
    if (place.hidden) {
      continue;
    }
    if (_faces[name] case final face?) {
      if (value(index) == 0) {
        close(face, index);
      } else {
        turn(face, index);
      }
    }
    for (final face in _offs[name] ?? const <String>[]) {
      close(face, index);
    }
    if (name == 'f') {
      if (monospaced.contains(value(index))) {
        turn('code', index);
      } else {
        close('code', index);
      }
    }
    switch (name) {
      case 'fs':
        size = value(index) ?? 24;
      case 'plain':
        size = 24;
      case 'pard':
        style = 0;
        level = null;
        item = null;
        tier = 0;
      case 'ls':
        item = value(index);
      case 'ilvl':
        tier = value(index) ?? 0;
      case 's':
        style = value(index) ?? 0;
      case 'outlinelevel':
        level = value(index);
    }
    if (place.apart == 0 && name == 'par') {
      paragraph(index);
      start = index + 1;
      // A paragraph between two rows parts their tables.
      table();
      continue;
    }
    if (place.apart == 0) {
      switch (name) {
        case 'trowd' when row == null:
          row = index;
          cell = index;
          header = false;
        case 'trhdr':
          header = true;
        case 'cell':
          // A row whose definition follows its cells starts with them.
          row ??= cell;
          ranges.add(
            _range(cell, index - cell + 1, {'': header ? 'th' : 'td'}),
          );
          cell = index + 1;
          start = index + 1;
          held.clear();
          continue;
        case 'row' when row != null:
          final from = row;
          if (rows.isEmpty) {
            first = ranges.length;
          }
          ranges.add(_range(from, index - from + 1, {'': 'tr'}));
          rows.add((from, index));
          row = null;
          header = false;
          cell = index + 1;
          start = index + 1;
          held.clear();
          continue;
        case 'nestcell' || 'nestrow':
          problems.add(
            _range(index, 1, {'message': 'a table within a table is not read'}),
          );
        case 'itap' when (value(index) ?? 1) > 1:
          problems.add(
            _range(index, 1, {'message': 'a table within a table is not read'}),
          );
      }
    }
    if (tokens[index].get('shows') != null || name == prose) {
      if (place.apart == 0 && name != 'par') {
        held.add(size);
      }
      sizes[size] = (sizes[size] ?? 0) + 1;
    }
  }
  // What follows the last paragraph mark, where it holds any text.
  final last = names.lastIndexOf('}');
  if (held.isNotEmpty && last >= start) {
    paragraph(last - 1);
  }
  table();
  for (final face in [...faces.keys]) {
    close(face, names.length - 1);
  }
  ranges.addAll(_separate(tokens, names, text, braces, closes));
  final body =
      styles[0]?.size ??
      (sizes.entries.toList()..sort(
            (one, other) => one.value != other.value
                ? other.value - one.value
                : one.key - other.key,
          ))
          .firstOrNull
          ?.key ??
      24;
  return (
    ranges: _grouped([
      for (final range in ranges)
        if (range.get('size') case final said? when '$said' == _points(body))
          ARange.from(range, {
            for (final MapEntry(:key, :value) in range.attributes.entries)
              if (key != 'size') key: value,
          })
        else
          range,
    ]),
    diagnostics: problems,
  );
}

/// The size, in points, every one of [held] is, where they agree.
String? _uniform(List<int> held) =>
    held.isNotEmpty && held.every((one) => one == held.first)
    ? _points(held.first)
    : null;

/// [half] points as points: `18` for 36, `11.5` for 23.
String _points(int half) => half.isEven ? '${half ~/ 2}' : '${half / 2}';

/// Where the body starts: past the last hidden destination directly within
/// the document group that comes before any text of the document's.
int _body(List<String> names, List<_Place> places, Map<int, String> braces) {
  var start = 1;
  var depth = 0;
  for (var index = 0; index < names.length; index++) {
    final name = names[index];
    if (name == '{') {
      depth++;
    } else if (name == '}') {
      depth--;
      if (depth == 1 && places[index].hidden) {
        start = index + 1;
      }
    } else if (!places[index].hidden &&
        places[index].apart == 0 &&
        (name == prose || name == '#character' || name == '#unicode')) {
      return start;
    }
  }
  return start;
}

/// For each `{` of [names], the index of the `}` that closes it.
Map<int, int> _closes(List<String> names) {
  final closes = <int, int>{};
  final open = <int>[];
  for (var index = 0; index < names.length; index++) {
    if (names[index] == '{') {
      open.add(index);
    } else if (names[index] == '}' && open.isNotEmpty) {
      closes[open.removeLast()] = index;
    }
  }
  return closes;
}

/// The paragraph styles of the stylesheet from [start] to [end]: each
/// entry's `\sN`, 0 where it has none, its name, and its `\fsN`.
Map<int, _Style> _styles(
  List<ARange> tokens,
  List<String> names,
  String Function(int index) text,
  int start,
  int end,
) {
  final styles = <int, _Style>{};
  var index = start + 2;
  while (index < end) {
    if (names[index] != '{') {
      index++;
      continue;
    }
    var depth = 0;
    int? number = 0;
    int? size;
    final faces = <String>{};
    final words = StringBuffer();
    var at = index;
    for (; at < end; at++) {
      final name = names[at];
      if (name == '{') {
        depth++;
      } else if (name == '}') {
        depth--;
        if (depth == 0) {
          break;
        }
      } else if (depth == 1) {
        final value = int.tryParse('${tokens[at].get('value') ?? ''}');
        switch (name) {
          case 's':
            number = value;
          case 'cs' || 'ds' || 'ts' || 'tsrowd':
            number = null;
          case 'fs':
            size = value;
          case '#text' || '#hidden':
            words.write(text(at));
          case final word when _faces.containsKey(word) && value != 0:
            faces.add(_faces[word]!);
        }
      }
    }
    final name = words.toString().split(';').first.trim();
    if (number != null && name.isNotEmpty) {
      styles[number] = (name: name, size: size, faces: faces);
    }
    index = at + 1;
  }
  return styles;
}

ARange _range(int start, int length, Map<String, String?> said) =>
    ranged(start, length, {
      for (final MapEntry(:key, :value) in said.entries)
        if (value != null) key: literal(value),
    });

/// The monospaced fonts of the font table from [start] to [end], by
/// number: those whose family is `\fmodern`, or whose name is one of
/// [_monospaced]. An entry runs from its `\fN` to the `;` that ends its
/// name, whether each is a group of its own, as Word writes them, or not,
/// as Cocoa does; only the text at the entry's own level is its name.
Set<int> _fonts(
  List<ARange> tokens,
  List<String> names,
  String Function(int index) text,
  int start,
  int end,
) {
  final fonts = <int>{};
  var depth = 0;
  int? number;
  var modern = false;
  final words = StringBuffer();
  for (var at = start + 1; at < end; at++) {
    final name = names[at];
    if (name == '{') {
      depth++;
    } else if (name == '}') {
      depth--;
    } else if (depth <= 1) {
      switch (name) {
        case 'f':
          number = int.tryParse('${tokens[at].get('value') ?? ''}');
          modern = false;
          words.clear();
        case 'fmodern':
          modern = true;
        case '#text' || '#hidden':
          final run = text(at);
          final stop = run.indexOf(';');
          words.write(stop < 0 ? run : run.substring(0, stop));
          if (stop >= 0 && number != null) {
            final plain = words.toString().toLowerCase().replaceAll(' ', '');
            if (modern || _monospaced.any(plain.startsWith)) {
              fonts.add(number);
            }
            number = null;
          }
      }
    }
  }
  return fonts;
}

/// [ranges], their list items grouped into lists as [listed] groups an
/// import's: each run of items of one kind and level held by one list over
/// them, which has no tokens of its own, and deeper items by the item
/// before them.
List<ARange> _grouped(List<ARange> ranges) {
  if (!ranges.any((range) => range.get('list') != null)) {
    return ranges;
  }
  final spans = [
    for (final range in ranges)
      (
        start: range.start,
        end: range.end,
        name: '${range.get('')}',
        said: stated(range.attributes),
      ),
  ];
  return [
    for (final span in listed(spans))
      _range(span.start, span.end - span.start, {'': span.name, ...span.said}),
  ];
}

/// The lists of the list table from [start] to [end]: each list's
/// `\listidN`, and the kind of list each of its levels is, in order: a
/// `ul` where the level's `\levelnfcN` is 23, a bullet, or its Cocoa
/// `\levelmarker` is one, and an `ol` otherwise.
Map<int, List<String>> _lists(
  List<ARange> tokens,
  List<String> names,
  String Function(int index) text,
  int start,
  int end,
) {
  const bullets = {'disc', 'circle', 'square', 'hyphen', 'check', 'diamond'};
  final lists = <int, List<String>>{};
  var depth = 0;
  var kinds = <String>[];
  int? id;
  var level = false;
  var bullet = false;
  var marker = false;
  for (var at = start + 1; at < end; at++) {
    final name = names[at];
    final value = int.tryParse('${tokens[at].get('value') ?? ''}');
    if (name == '{') {
      depth++;
      if (depth == 1) {
        kinds = [];
        id = null;
      }
    } else if (name == '}') {
      if (depth == 2 && level) {
        kinds.add(bullet ? 'ul' : 'ol');
        level = false;
      }
      if (depth == 3) {
        marker = false;
      }
      if (depth == 1 && id != null) {
        lists[id] = kinds;
      }
      depth--;
    } else {
      switch (name) {
        case 'listlevel':
          level = true;
          bullet = false;
        case 'levelnfc' when value == 23:
          bullet = true;
        case 'levelmarker':
          marker = true;
        case '#hidden' when marker && bullets.contains(text(at).trim()):
          bullet = true;
        case 'listid' when depth == 1:
          id = value;
      }
    }
  }
  return lists;
}

/// The list overrides of the table from [start] to [end]: the list each
/// `\lsN` names, by `N`.
Map<int, int> _overrides(
  List<ARange> tokens,
  List<String> names,
  int start,
  int end,
) {
  final overrides = <int, int>{};
  int? id;
  for (var at = start + 1; at < end; at++) {
    final value = int.tryParse('${tokens[at].get('value') ?? ''}');
    switch (names[at]) {
      case 'listid':
        id = value;
      case 'ls' when id != null && value != null:
        overrides[value] = id;
        id = null;
    }
  }
  return overrides;
}

/// The elements of the groups that stand apart from the paragraphs around
/// them: each footnote, each field whose instruction is a `HYPERLINK`, an
/// `a` over its result saying its target, and each picture, an `img`; but
/// a picture Word gives again in `\nonshppict`, for readers that know no
/// other, and Cocoa's `\NeXTGraphic`, which says its file as `src`.
List<ARange> _separate(
  List<ARange> tokens,
  List<String> names,
  String Function(int index) text,
  Map<int, String> braces,
  Map<int, int> closes,
) {
  final found = <ARange>[];
  // The text of the tokens from [from] to [to], hidden or not.
  String words(int from, int to) => [
    for (var at = from; at <= to; at++)
      if (names[at] == prose || names[at] == '#hidden') text(at),
  ].join();
  final skipped = <int>{};
  for (final MapEntry(key: at, value: word) in braces.entries) {
    final close = closes[at];
    if (close == null) {
      continue;
    }
    switch (word) {
      case 'nonshppict':
        for (var inner = at; inner <= close; inner++) {
          skipped.add(inner);
        }
      case 'footnote':
        found.add(_range(at, close - at + 1, {'': 'footnote'}));
      case 'field':
        int? result;
        String? target;
        for (final MapEntry(key: inner, value: part) in braces.entries) {
          if (inner <= at || inner >= close) {
            continue;
          }
          if (part == 'fldinst') {
            final link = RegExp(r'HYPERLINK\s+"([^"]*)"')
                .firstMatch(words(inner, closes[inner] ?? close));
            target = link?[1];
          } else if (part == 'fldrslt') {
            result = inner;
          }
        }
        if (result != null && target != null) {
          final end = closes[result] ?? close;
          found.add(
            _range(result, end - result + 1, {'': 'a', 'href': target}),
          );
        }
    }
  }
  for (final MapEntry(key: at, value: word) in braces.entries) {
    final close = closes[at];
    if (close == null || skipped.contains(at)) {
      continue;
    }
    if (word == 'pict') {
      found.add(_range(at, close - at + 1, {'': 'img'}));
    } else if (word == 'NeXTGraphic') {
      final file = words(at, close).trim().split(' ').first;
      found.add(_range(at, close - at + 1, {'': 'img', 'src': file}));
    }
  }
  return found;
}

/// The authors of the revision table from [start] to [end], in order: each
/// entry's text, to its `;`.
List<String> _authors(
  List<String> names,
  String Function(int index) text,
  int start,
  int end,
) {
  final authors = <String>[];
  final words = StringBuffer();
  var depth = 0;
  for (var at = start + 1; at < end; at++) {
    switch (names[at]) {
      case '{':
        depth++;
        words.clear();
      case '}':
        if (depth == 1) {
          authors.add(words.toString().split(';').first.trim());
        }
        depth--;
      case '#text' || '#hidden' when depth == 1:
        words.write(text(at));
    }
  }
  return authors;
}

/// A revision's packed date as ISO 8601, to the minute: its minute, hour,
/// day, month and years since 1900, from its lowest bits up.
String _dated(int packed) {
  final bits = packed & 0xFFFFFFFF;
  String two(int value) => value.toString().padLeft(2, '0');
  final year = ((bits >> 20) & 0x1FF) + 1900;
  return '$year-${two((bits >> 16) & 0xF)}-${two((bits >> 11) & 0x1F)}'
      'T${two((bits >> 6) & 0x1F)}:${two(bits & 0x3F)}';
}
