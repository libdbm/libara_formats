part of 'markdown.dart';

/// How Markdown represents its elements, for its structural edits: see
/// `notation.dart`.
final class _Markdown implements Notation {
  const _Markdown();

  @override
  String get syntax => 'markdown';

  @override
  String? opening(String name, Map<String, String> said, String prefix) =>
      switch (name) {
        'em' => '*',
        'strong' => '**',
        'code' => '`',
        'a' => '[',
        'h1' ||
        'h2' ||
        'h3' ||
        'h4' ||
        'h5' ||
        'h6' => '${'#' * int.parse(name.substring(1))} ',
        'blockquote' => '> ',
        'ul' || 'li' => '- ',
        'ol' => '${said['start'] ?? 1}. ',
        'pre' => '```${_language(said)}\n$prefix',
        // A table is its rows, a row a line of bars, and the ruling under
        // the head is written when the table is (see `_ruled`).
        'table' => '',
        'tr' => '|',
        'td' || 'th' => ' ',
        _ => null,
      };

  /// A rule and a table stand on lines of their own; a break is two
  /// spaces ending its line. An empty table has a head, its ruling, and
  /// one row, two columns wide, since a table of one column of bars reads
  /// as a head with no body.
  @override
  String? empty(String name, Map<String, String> said, String prefix) =>
      switch (name) {
        'hr' => '---\n$prefix',
        'br' => '  \n$prefix',
        'img' => '![${said['alt'] ?? ''}](${_destination(said['src'] ?? '')})',
        'table' => '|  |  |\n$prefix| --- | --- |\n$prefix|  |  |\n$prefix',
        _ => null,
      };

  @override
  String? closing(
    String name,
    Map<String, String> said,
    String prefix,
  ) => switch (name) {
    'em' => '*',
    'strong' => '**',
    'code' => '`',
    'a' =>
      '](${_destination(said['href'] ?? '')}'
          '${said['title'] == null ? '' : ' "${said['title']!.replaceAll('"', r'\"')}"'})',
    'pre' => '\n$prefix```',
    'table' => '',
    'tr' => '\n$prefix',
    'td' || 'th' => ' |',
    _ => null,
  };

  @override
  String? wrapped(
    String name,
    Map<String, String> said,
    String words,
    String prefix,
  ) {
    final opened = opening(name, said, prefix);
    if (opened == null) {
      return null;
    }
    if (name == 'blockquote') {
      // A quote marks every line it holds, at the column its first line's
      // words begin.
      final lines = words.split('\n');
      return [
        '$opened${lines.first}',
        for (final line in lines.skip(1))
          '${line.substring(0, min(prefix.length, line.length))}$opened'
              '${line.substring(min(prefix.length, line.length))}',
      ].join('\n');
    }
    return '$opened$words${closing(name, said, prefix) ?? ''}';
  }

  @override
  String? recast(
    String old,
    String name,
    Map<String, String> said,
    String words,
  ) {
    const runs = {'em', 'strong'};
    const lists = {'ul', 'ol'};
    final heading = RegExp(r'^h[1-6]$');
    if (runs.contains(old) && runs.contains(name)) {
      final mark = words.isEmpty ? '*' : words[0];
      return name == 'em' ? mark : mark * 2;
    }
    if (heading.hasMatch(old) &&
        heading.hasMatch(name) &&
        words.trimLeft().startsWith('#')) {
      return words.replaceFirst(
        RegExp('#+'),
        '#' * int.parse(name.substring(1)),
      );
    }
    if (lists.contains(old) && lists.contains(name)) {
      return words.replaceFirst(
        RegExp(r'[-+*]|\d{1,9}[.)]'),
        name == 'ul' ? '-' : '${said['start'] ?? 1}.',
      );
    }
    return null;
  }

  /// The markers before [at] on its line, a quote's angles kept and the
  /// rest made spaces, so a list's content keeps its column.
  @override
  String prefix(Layered<int> document, int at) {
    final start = line(document, at);
    final head = covered(document, span(start, at - start));
    final markers = RegExp(r'^[ \t>]*(?:(?:[-+*]|\d{1,9}[.)])[ \t]+[ \t>]*)*')
        .stringMatch(head)!;
    return markers.replaceAll(RegExp(r'[^ \t>]'), ' ');
  }

  @override
  String? lacking(String name, Map<String, String> said) =>
      name == 'a' && said['href'] == null
      ? 'a link closes with where it goes, as href'
      : null;

  /// A list's own tokens are its items' markers, which a list inside it
  /// owns where it holds them; a picture is one token and has nothing to
  /// take away but itself.
  @override
  (String, Set<String>)? owns(String name) => switch (name) {
    'ul' || 'ol' => ('li', const {'ul', 'ol'}),
    'img' => null,
    _ => (name, {name}),
  };

  /// A list made of blocks gives each a marker, as a tight list; one made
  /// of items standing after an item holds them in under it.
  @override
  (Range, String)? listed(
    Layered<int> document,
    String name,
    Map<String, String> said,
    ARange range,
  ) {
    final stretch = _stretch(document, range);
    if ((name != 'ul' && name != 'ol') || stretch == null) {
      return null;
    }
    final prefix = this.prefix(document, stretch.start);
    final tops = _tops(document, range);
    if (tops.every((one) => '${one.get('')}' == 'li')) {
      final words = covered(document, stretch);
      final width = _marker.stringMatch(words)?.length ?? 2;
      return (stretch, _held(words, prefix, ' ' * width));
    }
    final opened = opening(name, said, prefix)!;
    final items = [
      for (final top in tops)
        switch ((
          covered(document, _stretch(document, top)!),
          '${top.get('')}',
        )) {
          // A list in the run gives up its items as they stand.
          (final words, 'ul' || 'ol') => words,
          (final words, _) => _held(words, prefix, opened),
        },
    ];
    final from = _stretch(document, tops.first)!.start;
    return (
      span(from, _stretch(document, tops.last)!.end - from),
      items.join('\n$prefix'),
    );
  }

  /// A list inside an item is taken out a level, its indent taken off;
  /// any other list, or an item, gives up its markers, blank lines parting
  /// what it held from what stands around it.
  @override
  (Range, String)? unlisted(Layered<int> document, ARange element) {
    final name = '${element.get('')}';
    final stretch = _stretch(document, element);
    if (!{'ul', 'ol', 'li'}.contains(name) || stretch == null) {
      return null;
    }
    final prefix = this.prefix(document, stretch.start);
    final blank = prefix.trimRight();
    final holding = _holding(document, element, {'li'});
    if (name != 'li' && holding != null) {
      final start = line(document, stretch.start);
      final outer = this.prefix(document, _stretch(document, holding)!.start);
      final width = prefix.length - outer.length;
      final lines = covered(
        document,
        span(start, stretch.end - start),
      ).split('\n');
      return (
        span(start, stretch.end - start),
        [for (final line in lines) _outdented(line, outer.length, width)]
            .join('\n'),
      );
    }
    String freed(ARange item) =>
        _freed(covered(document, _stretch(document, item)!), prefix);
    if (name != 'li') {
      return (
        stretch,
        [for (final item in _tops(document, element, inside: true)) freed(item)]
            .join('\n$blank\n$prefix'),
      );
    }
    final list = _holding(document, element, {'ul', 'ol'}, same: true)!;
    final start = line(document, stretch.start);
    return (
      span(start, stretch.end - start),
      [
        if (list.start < element.start) '$blank\n',
        '$prefix${freed(element)}',
        if (element.end < list.end) '\n$blank',
      ].join(),
    );
  }
}

/// A list item's marker, with the space after it.
final _marker = RegExp(r'^(?:[-+*]|\d{1,9}[.)])[ \t]+');

/// The text [range]'s tokens stand over in [document], or null where it
/// has none.
Range? _stretch(Layered<int> document, ARange range) {
  final tokens = document.span(2, range);
  if (tokens.isEmpty) {
    return null;
  }
  final from = tokens.first.$2.start;
  return span(from, tokens.last.$2.end - from);
}

/// The elements of [document] in [range] that no other there holds; with
/// [inside], those [range], an element, holds, itself left out, though
/// another may stand over the same tokens.
List<ARange> _tops(Layered<int> document, ARange range, {bool inside = false}) {
  final held =
      [
        for (final (_, one) in document.within(3, range))
          if (!inside ||
              one.start != range.start ||
              one.length != range.length ||
              one.get('') != range.get(''))
            one,
      ]..sort(
        (one, other) => one.start != other.start
            ? one.start - other.start
            : other.length - one.length,
      );
  final tops = <ARange>[];
  for (final one in held) {
    if (tops.isEmpty || one.start >= tops.last.end) {
      tops.add(one);
    }
  }
  return tops;
}

/// The innermost element of [document] called one of [names] holding
/// [element]; with [same], one over the same tokens may.
ARange? _holding(
  Layered<int> document,
  ARange element,
  Set<String> names, {
  bool same = false,
}) {
  ARange? found;
  for (final (_, one) in document.markers(3)) {
    if (names.contains('${one.get('')}') &&
        one.start <= element.start &&
        element.end <= one.end &&
        (same || one.length > element.length) &&
        (found == null || one.length < found.length)) {
      found = one;
    }
  }
  return found;
}

/// [words] opened by [indent], and every line after the first held in by
/// as many spaces past the [prefix] it carries on under.
String _held(String words, String prefix, String indent) {
  final lines = words.split('\n');
  return [
    '$indent${lines.first}',
    for (final line in lines.skip(1))
      line.length <= prefix.length || line.substring(prefix.length).trim() == ''
          ? line
          : '${line.substring(0, prefix.length)}${' ' * indent.length}'
                '${line.substring(prefix.length)}',
  ].join('\n');
}

/// [words], an item written under [prefix], without its marker and with
/// the indent under it taken off, a blank line before a list that follows
/// its words.
String _freed(String words, String prefix) {
  final marker = _marker.stringMatch(words) ?? '';
  final lines = words.split('\n');
  final written = [lines.first.substring(marker.length)];
  for (final line in lines.skip(1)) {
    final kept = _outdented(line, prefix.length, marker.length);
    final said = kept.substring(min(prefix.length, kept.length));
    if (_marker.hasMatch(said) &&
        written.last.trim().isNotEmpty &&
        !_marker.hasMatch(written.last.trimLeft())) {
      written.add(prefix.trimRight());
    }
    written.add(kept);
  }
  return written.join('\n');
}

/// [line] with the [width] columns from [at] taken off, where they are
/// blank.
String _outdented(String line, int at, int width) =>
    line.length >= at + width && line.substring(at, at + width).trim() == ''
    ? line.replaceRange(at, at + width, '')
    : line;

/// What a fence says its code is in, from a `class` of `language-`.
String _language(Map<String, String> said) {
  final held = said['class'] ?? '';
  return held.startsWith('language-') ? held.substring(9) : '';
}

/// [href] as a link's destination is written, in angles where it holds
/// what would end it.
String _destination(String href) => href.contains(RegExp(r'[\s()<>]'))
    ? '<${href.replaceAll('<', r'\<').replaceAll('>', r'\>')}>'
    : href;
