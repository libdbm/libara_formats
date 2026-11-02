// Writes, beside each RTF sample in test/samples/rtf/, the reading the
// tests hold the RTF format and importer to: <name>.json.
//
// The reading that decides is LibreOffice's, for what Word and LibreOffice
// wrote, and Cocoa's textutil, for what TextEdit and Pages wrote: each read
// as HTML. pandoc's reading is kept beside it, with the places the two
// disagree, and decides nothing: its RTF reader misreads these samples.
//
// Each reading is the blocks in reading order, each its name and text (an
// item says its list and level), and the faces, each its name and text (a
// link says its href).
//
// Needs macOS, for textutil, LibreOffice in /Applications, and pandoc.
//
//   dart run tool/rtf_references.dart

import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

const _soffice = '/Applications/LibreOffice.app/Contents/MacOS/soffice';

/// The fonts read as monospaced, by name with spaces and any suffix such
/// as `-Regular` or `PSMT` taken away, in lower case.
const _monospaced = {
  'courier',
  'couriernew',
  'menlo',
  'monaco',
  'sfmono',
  'andalemono',
  'consolas',
  'lucidaconsole',
};

typedef _Reading = ({
  List<Map<String, Object>> blocks,
  List<Map<String, Object>> faces,
});

void main() {
  final directory = Directory('test/samples/rtf');
  final samples =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.rtf'))
          .toList()
        ..sort((one, other) => one.path.compareTo(other.path));
  for (final sample in samples) {
    final name = sample.uri.pathSegments.last.replaceAll('.rtf', '');
    final cocoa = name.endsWith('-textedit') || name.endsWith('-pages');
    final deciding = cocoa ? _textutil(sample) : _libreoffice(sample);
    final pandoc = _pandoc(sample);
    final reference = {
      'reference': cocoa ? 'textutil' : 'libreoffice',
      'blocks': deciding.blocks,
      'faces': deciding.faces,
      'pandoc': {'blocks': pandoc.blocks, 'faces': pandoc.faces},
      'disagreements': _disagreements(deciding, pandoc),
    };
    final target = File('${directory.path}/$name.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(reference)}\n',
      );
    stdout.writeln(target.path);
  }
}

/// [executable] run with [arguments], its output; the script stops where it
/// fails.
String _command(String executable, List<String> arguments) {
  final result = Process.runSync(
    executable,
    arguments,
    environment: {'TZ': 'UTC'},
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    exit(result.exitCode);
  }
  return '${result.stdout}';
}

/// [sample] as LibreOffice reads it.
_Reading _libreoffice(File sample) {
  final staging = Directory.systemTemp.createTempSync('rtf_references');
  try {
    _command(_soffice, [
      '--headless',
      '--convert-to',
      'html',
      '--outdir',
      staging.path,
      sample.path,
    ]);
    final name = sample.uri.pathSegments.last.replaceAll('.rtf', '.html');
    return _read(File('${staging.path}/$name').readAsStringSync());
  } finally {
    staging.deleteSync(recursive: true);
  }
}

/// [sample] as Cocoa's text system reads it.
_Reading _textutil(File sample) => _read(
  _command('/usr/bin/textutil', ['-convert', 'html', '-stdout', sample.path]),
);

/// The blocks and faces of an HTML reading.
_Reading _read(String text) {
  final document = html.parse(text);
  // textutil sets faces by class: each class's declarations, by its name.
  final classes = <String, String>{};
  for (final style in document.querySelectorAll('style')) {
    for (final match in RegExp(
      r'([a-z]+)\.([\w-]+)\s*\{([^}]*)\}',
    ).allMatches(style.text)) {
      classes['${match[1]}.${match[2]}'] = match[3]!.toLowerCase();
    }
  }
  final blocks = <Map<String, Object>>[];
  final faces = <Map<String, Object>>[];
  final body = document.body;
  if (body == null) {
    return (blocks: blocks, faces: faces);
  }
  // LibreOffice puts the footnotes' text at the end, apart from its mark,
  // and numbers both: the numbers are not the text's.
  for (final mark in body.querySelectorAll(
    'a.sdfootnoteanc, a.sdfootnotesym',
  )) {
    final holder = mark.parent;
    mark.remove();
    if (holder != null && holder.localName == 'sup' && holder.text.isEmpty) {
      holder.remove();
    }
  }
  for (final note in body.querySelectorAll('div[id^=sdfootnote]')) {
    faces.add({'name': 'footnote', 'text': _words(note.text)});
    note.remove();
  }
  _walk(body, blocks, faces, classes, const []);
  return (blocks: blocks, faces: faces);
}

const _blocks = {'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'td', 'th'};

/// [node]'s blocks and faces, [lists] being the lists that hold it.
void _walk(
  Element node,
  List<Map<String, Object>> blocks,
  List<Map<String, Object>> faces,
  Map<String, String> classes,
  List<String> lists,
) {
  for (final kid in node.children) {
    final name = kid.localName!;
    if (name == 'ul' || name == 'ol') {
      _walk(kid, blocks, faces, classes, [...lists, name]);
    } else if (name == 'li') {
      final own = kid.clone(true);
      for (final nested in own.querySelectorAll('ul, ol')) {
        nested.remove();
      }
      blocks.add({
        'name': 'li',
        'text': _words(own.text),
        'list': lists.last,
        'level': lists.length,
      });
      _faces(own, faces, classes);
      for (final nested in kid.children) {
        if (nested.localName case final kind?
            when kind == 'ul' || kind == 'ol') {
          _walk(nested, blocks, faces, classes, [...lists, kind]);
        }
      }
    } else if (_blocks.contains(name)) {
      final words = _words(kid.text);
      if (words.isNotEmpty) {
        blocks.add({'name': name, 'text': words});
        _faces(kid, faces, classes);
      }
    } else if (name == 'blockquote') {
      _walk(kid, blocks, faces, classes, lists);
    } else {
      _walk(kid, blocks, faces, classes, lists);
    }
  }
}

/// The faces within [block], each innermost run of a face once.
void _faces(
  Element block,
  List<Map<String, Object>> faces,
  Map<String, String> classes,
) {
  for (final element in block.querySelectorAll('*')) {
    final name = element.localName!;
    final words = _words(element.text);
    if (words.isEmpty) {
      continue;
    }
    final style = [
      element.attributes['style'] ?? '',
      for (final one in element.classes) classes['$name.$one'] ?? '',
    ].join(';').toLowerCase();
    final face = switch (name) {
      'b' || 'strong' => 'strong',
      'i' || 'em' => 'em',
      'u' => 'u',
      's' || 'strike' || 'del' => 's',
      'sup' => 'sup',
      'sub' => 'sub',
      'code' || 'tt' => 'code',
      'a' when element.attributes['href'] != null => 'a',
      _ => null,
    };
    if (face == 'a') {
      faces.add({
        'name': 'a',
        'text': words,
        'href': element.attributes['href']!,
      });
    } else if (face != null) {
      faces.add({'name': face, 'text': words});
    }
    if (style.contains('underline')) {
      faces.add({'name': 'u', 'text': words});
    }
    if (style.contains('line-through')) {
      faces.add({'name': 's', 'text': words});
    }
    final font =
        (element.attributes['face'] ??
                RegExp(r'font[^;]*').firstMatch(style)?[0] ??
                '')
            .toLowerCase();
    if (font.isNotEmpty &&
        _monospaced.any(
          (one) => font.replaceAll(RegExp(r'[\s-]'), '').contains(one),
        )) {
      faces.add({'name': 'code', 'text': words});
    }
  }
}

/// [text] with its runs of white space made one space, and trimmed.
String _words(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [sample] as pandoc reads it.
_Reading _pandoc(File sample) {
  final tree = jsonDecode(
    _command('pandoc', ['-f', 'rtf', '-t', 'json', sample.path]),
  ) as Map;
  final blocks = <Map<String, Object>>[];
  final faces = <Map<String, Object>>[];
  void walk(List<Object?> items, List<String> lists, {String? as}) {
    for (final item in items.cast<Map>()) {
      final content = item['c'];
      switch (item['t']) {
        case 'Header':
          final [level, _, inlines] = content as List;
          blocks.add({
            'name': 'h$level',
            'text': _inline(inlines as List, faces),
          });
        case 'Para' || 'Plain':
          final text = _inline(content as List, faces);
          if (text.isNotEmpty) {
            blocks.add({
              'name': as ?? 'p',
              'text': text,
              if (as == 'li') 'list': lists.last,
              if (as == 'li') 'level': lists.length,
            });
          }
        case 'CodeBlock':
          blocks.add({
            'name': 'pre',
            'text': _words('${(content as List)[1]}'),
          });
        case 'BlockQuote':
          walk(content as List, lists);
        case 'BulletList' || 'OrderedList':
          final kind = item['t'] == 'BulletList' ? 'ul' : 'ol';
          final entries = kind == 'ul'
              ? content as List
              : (content as List)[1] as List;
          for (final entry in entries.cast<List>()) {
            walk(entry, [...lists, kind], as: 'li');
          }
        case 'Table':
          for (final cell in _cells(content)) {
            walk(cell, lists, as: 'td');
          }
        case 'Div':
          walk((content as List)[1] as List, lists, as: as);
      }
    }
  }

  walk(tree['blocks'] as List, const []);
  return (blocks: blocks, faces: faces);
}

/// The contents of every cell of a pandoc table, row by row.
Iterable<List<Object?>> _cells(Object? table) sync* {
  if (table is Map && table['t'] == 'Cell') {
    yield (table['c'] as List).last as List<Object?>;
  } else if (table is List) {
    for (final one in table) {
      yield* _cells(one);
    }
  } else if (table is Map) {
    for (final one in table.values) {
      yield* _cells(one);
    }
  }
}

/// The words of pandoc [inlines], recording its faces in [faces].
String _inline(List<Object?> inlines, List<Map<String, Object>> faces) {
  final words = StringBuffer();
  for (final item in inlines.cast<Map>()) {
    final content = item['c'];
    switch (item['t']) {
      case 'Str':
        words.write(content);
      case 'Space' || 'SoftBreak' || 'LineBreak':
        words.write(' ');
      case 'Code':
        final text = '${(content as List)[1]}';
        words.write(text);
        faces.add({'name': 'code', 'text': _words(text)});
      case 'Strong' ||
          'Emph' ||
          'Underline' ||
          'Strikeout' ||
          'Superscript' ||
          'Subscript':
        final text = _inline(content as List, faces);
        words.write(text);
        faces.add({
          'name': const {
            'Strong': 'strong',
            'Emph': 'em',
            'Underline': 'u',
            'Strikeout': 's',
            'Superscript': 'sup',
            'Subscript': 'sub',
          }[item['t']]!,
          'text': _words(text),
        });
      case 'Link':
        final [_, inner, target] = content as List;
        final text = _inline(inner as List, faces);
        words.write(text);
        faces.add({
          'name': 'a',
          'text': _words(text),
          'href': '${(target as List)[0]}',
        });
      case 'Span':
        words.write(_inline((content as List)[1] as List, faces));
      case 'Note':
        final notes = <Map<String, Object>>[];
        final text = [
          for (final block in (content as List).cast<Map>())
            if (block['c'] is List) _inline(block['c'] as List, notes),
        ].join(' ');
        faces.add({'name': 'footnote', 'text': _words(text)});
    }
  }
  return words.toString();
}

/// Where [deciding] and [pandoc] differ: each block or face one has and the
/// other does not.
List<String> _disagreements(_Reading deciding, _Reading pandoc) {
  String block(Map<String, Object> one) => '${one['name']} "${one['text']}"';
  final ours = [for (final one in deciding.blocks) block(one)];
  final theirs = [for (final one in pandoc.blocks) block(one)];
  final faces = [for (final one in deciding.faces) block(one)];
  final others = [for (final one in pandoc.faces) block(one)];
  return [
    for (final one in ours)
      if (!theirs.contains(one)) 'pandoc lacks the block $one',
    for (final one in theirs)
      if (!ours.contains(one)) 'pandoc adds the block $one',
    for (final one in faces)
      if (!others.contains(one)) 'pandoc lacks the face $one',
    for (final one in others)
      if (!faces.contains(one)) 'pandoc adds the face $one',
  ];
}
