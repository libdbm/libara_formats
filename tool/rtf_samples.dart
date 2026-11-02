// Writes the Word documents the RTF samples are made from, into
// test/samples/rtf/:
//
// - features.docx: styles, faces, lists to three levels, a table, a link
//   and a footnote, with no revisions;
// - revisions.docx: an insertion, a deletion and a change of formatting,
//   by two authors;
// - degenerate.docx: Normal paragraphs formatted by hand, its headings in
//   16 points and its text in 12.
//
// Each is its XML parts, zipped by /usr/bin/zip with fixed dates, so a
// second run writes the same bytes. Then each is saved as RTF by
// LibreOffice, <name>-libreoffice.rtf, and by Cocoa's text system, as
// TextEdit saves it, <name>-textedit.rtf; both write the same bytes each
// run. Word's and Pages' RTF, <name>-word.rtf and <name>-pages.rtf, are
// saved by hand.
//
// Needs macOS, for textutil, and LibreOffice in /Applications.
//
//   dart run tool/rtf_samples.dart

import 'dart:io';

const _main =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

const _relationships =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// Every file is dated this, so the zips do not change between runs.
final _date = DateTime.utc(2026, 1, 1);

const _lorem =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do '
    'eiusmod tempor incididunt ut labore et dolore magna aliqua.';

void main() {
  final directory = Directory('test/samples/rtf')..createSync(recursive: true);
  for (final (name, document, footnotes) in [
    ('features', _features, true),
    ('revisions', _revisions, false),
    ('degenerate', _degenerate, false),
  ]) {
    final file = File('${directory.path}/$name.docx');
    _zip(file, _parts(document, footnotes: footnotes));
    stdout.writeln(file.path);
    _libreoffice(file, File('${directory.path}/$name-libreoffice.rtf'));
    _command('/usr/bin/textutil', [
      '-convert',
      'rtf',
      '-output',
      '${directory.path}/$name-textedit.rtf',
      file.path,
    ]);
  }
}

const _soffice = '/Applications/LibreOffice.app/Contents/MacOS/soffice';

/// [source] saved as RTF by LibreOffice, as [target].
void _libreoffice(File source, File target) {
  final staging = Directory.systemTemp.createTempSync('rtf_samples');
  try {
    _command(_soffice, [
      '--headless',
      '--convert-to',
      'rtf',
      '--outdir',
      staging.path,
      source.path,
    ]);
    final name = source.uri.pathSegments.last.replaceAll('.docx', '.rtf');
    File('${staging.path}/$name').copySync(target.path);
    stdout.writeln(target.path);
  } finally {
    staging.deleteSync(recursive: true);
  }
}

/// [executable] run with [arguments], stopping the script where it fails.
void _command(String executable, List<String> arguments, {String? directory}) {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: directory,
    environment: {'TZ': 'UTC'},
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    exit(result.exitCode);
  }
}

/// A document's parts, by their paths in the package.
Map<String, String> _parts(String body, {required bool footnotes}) => {
  '[Content_Types].xml': _types(footnotes: footnotes),
  '_rels/.rels': _relations({
    'rId1': ('officeDocument', 'word/document.xml', false),
  }),
  'word/_rels/document.xml.rels': _relations({
    'rId1': ('styles', 'styles.xml', false),
    'rId2': ('numbering', 'numbering.xml', false),
    'rId3': ('settings', 'settings.xml', false),
    if (footnotes) 'rId4': ('footnotes', 'footnotes.xml', false),
    'rId5': ('hyperlink', 'https://example.com/lorem', true),
  }),
  'word/document.xml': _xml(
    '<w:document $_main><w:body>$body</w:body></w:document>',
  ),
  'word/styles.xml': _styles,
  'word/numbering.xml': _numbering,
  'word/settings.xml': _settings(footnotes: footnotes),
  if (footnotes) 'word/footnotes.xml': _footnotes,
};

String _xml(String content) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n$content';

String _types({required bool footnotes}) {
  const office =
      'application/vnd.openxmlformats-officedocument.wordprocessingml';
  final overrides = {
    '/word/document.xml': '$office.document.main+xml',
    '/word/styles.xml': '$office.styles+xml',
    '/word/numbering.xml': '$office.numbering+xml',
    '/word/settings.xml': '$office.settings+xml',
    if (footnotes) '/word/footnotes.xml': '$office.footnotes+xml',
  };
  return _xml(
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" '
    'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '${[for (final MapEntry(:key, :value) in overrides.entries) '<Override PartName="$key" ContentType="$value"/>'].join()}'
    '</Types>',
  );
}

/// Relationships, each by its id: its type, its target, and whether the
/// target is outside the package.
String _relations(Map<String, (String, String, bool)> relations) => _xml(
  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  '${[for (final MapEntry(key: id, value: (type, target, external)) in relations.entries) '<Relationship Id="$id" Type="$_relationships/$type" Target="$target"'
        '${external ? ' TargetMode="External"' : ''}/>'].join()}'
  '</Relationships>',
);

String _style(
  String id,
  String name, {
  String paragraph = '',
  String run = '',
}) =>
    '<w:style w:type="paragraph" w:styleId="$id"><w:name w:val="$name"/>'
    '${id == 'Normal' ? '' : '<w:basedOn w:val="Normal"/>'}'
    '<w:qFormat/><w:pPr>$paragraph</w:pPr><w:rPr>$run</w:rPr></w:style>';

final _styles = _xml(
  '<w:styles $_main>'
  '<w:docDefaults><w:rPrDefault><w:rPr>'
  '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>'
  '<w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults>'
  '${_style('Normal', 'Normal')}'
  '${_style('Title', 'Title', run: '<w:sz w:val="56"/>')}'
  '${_style('Heading1', 'heading 1', paragraph: '<w:outlineLvl w:val="0"/>', run: '<w:b/><w:sz w:val="32"/>')}'
  '${_style('Heading2', 'heading 2', paragraph: '<w:outlineLvl w:val="1"/>', run: '<w:b/><w:sz w:val="28"/>')}'
  '${_style('Heading3', 'heading 3', paragraph: '<w:outlineLvl w:val="2"/>', run: '<w:b/><w:i/>')}'
  '${_style('Quote', 'Quote', paragraph: '<w:ind w:left="720"/>', run: '<w:i/>')}'
  '${_style('ListParagraph', 'List Paragraph', paragraph: '<w:ind w:left="720"/>')}'
  '<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/>'
  '<w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>'
  '<w:style w:type="character" w:styleId="FootnoteReference">'
  '<w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>'
  '</w:styles>',
);

/// One list level: its format, the text of its marker, and its indent.
String _level(int level, String format, String text) =>
    '<w:lvl w:ilvl="$level"><w:start w:val="1"/><w:numFmt w:val="$format"/>'
    '<w:lvlText w:val="$text"/><w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="${720 * (level + 1)}" w:hanging="360"/></w:pPr></w:lvl>';

final _numbering = _xml(
  '<w:numbering $_main>'
  '<w:abstractNum w:abstractNumId="0">'
  '${_level(0, 'bullet', '•')}${_level(1, 'bullet', 'o')}${_level(2, 'bullet', '▪')}'
  '</w:abstractNum>'
  '<w:abstractNum w:abstractNumId="1">'
  '${_level(0, 'decimal', '%1.')}${_level(1, 'lowerLetter', '%2.')}${_level(2, 'lowerRoman', '%3.')}'
  '</w:abstractNum>'
  '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
  '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
  '</w:numbering>',
);

String _settings({required bool footnotes}) => _xml(
  '<w:settings $_main>'
  '${footnotes ? '<w:footnotePr><w:footnote w:id="-1"/><w:footnote w:id="0"/></w:footnotePr>' : ''}'
  '</w:settings>',
);

final _footnotes = _xml(
  '<w:footnotes $_main>'
  '<w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>'
  '<w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>'
  '<w:footnote w:id="1"><w:p>'
  '<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteRef/></w:r>'
  '${_run(' Ut enim ad minim veniam, quis nostrud exercitation.')}'
  '</w:p></w:footnote>'
  '</w:footnotes>',
);

/// [text] escaped for XML.
String _escaped(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// A run of [text] with run properties [properties].
String _run(String text, [String properties = '']) =>
    '<w:r>${properties.isEmpty ? '' : '<w:rPr>$properties</w:rPr>'}'
    '<w:t xml:space="preserve">${_escaped(text)}</w:t></w:r>';

/// A paragraph of [style] holding [runs], an item of list [list] at
/// [level] where [list] is given.
String _paragraph(String runs, {String? style, int? list, int level = 0}) {
  final properties = [
    if (style != null) '<w:pStyle w:val="$style"/>',
    if (list != null)
      '<w:numPr><w:ilvl w:val="$level"/><w:numId w:val="$list"/></w:numPr>',
  ].join();
  return '<w:p>${properties.isEmpty ? '' : '<w:pPr>$properties</w:pPr>'}$runs</w:p>';
}

/// A table cell holding [text], bold where it is a header.
String _cell(String text, {bool header = false}) =>
    '<w:tc><w:tcPr><w:tcW w:w="4320" w:type="dxa"/></w:tcPr>'
    '${_paragraph(_run(text, header ? '<w:b/>' : ''))}</w:tc>';

String _row(List<String> cells, {bool header = false}) =>
    '<w:tr>${header ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}'
    '${[for (final cell in cells) _cell(cell, header: header)].join()}</w:tr>';

final _features = [
  _paragraph(_run('Lorem Ipsum'), style: 'Title'),
  _paragraph(_run('Dolor sit amet'), style: 'Heading1'),
  _paragraph(
    [
      _run('Lorem '),
      _run('ipsum', '<w:b/>'),
      _run(' dolor '),
      _run('sit', '<w:i/>'),
      _run(' amet, '),
      _run('consectetur', '<w:u w:val="single"/>'),
      _run(' adipiscing '),
      _run('elit', '<w:strike/>'),
      _run(', sed do e'),
      _run('2', '<w:vertAlign w:val="superscript"/>'),
      _run(' and H'),
      _run('2', '<w:vertAlign w:val="subscript"/>'),
      _run('O, '),
      _run(
        'tempor()',
        '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/>',
      ),
      _run(' and '),
      _run('bold italic', '<w:b/><w:i/>'),
      _run('. See '),
      '<w:hyperlink r:id="rId5">${_run('the lorem site', '<w:rStyle w:val="Hyperlink"/>')}</w:hyperlink>',
      _run('.'),
      '<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference w:id="1"/></w:r>',
    ].join(),
  ),
  _paragraph(_run('Consectetur adipiscing'), style: 'Heading2'),
  _paragraph(_run('Sed do eiusmod'), style: 'ListParagraph', list: 1),
  _paragraph(
    _run('Tempor incididunt'),
    style: 'ListParagraph',
    list: 1,
    level: 1,
  ),
  _paragraph(_run('Ut labore'), style: 'ListParagraph', list: 1, level: 2),
  _paragraph(_run('Et dolore'), style: 'ListParagraph', list: 1, level: 1),
  _paragraph(_run('Magna aliqua'), style: 'ListParagraph', list: 1),
  _paragraph(_run('Ut enim ad minim'), style: 'ListParagraph', list: 2),
  _paragraph(_run('Quis nostrud'), style: 'ListParagraph', list: 2),
  _paragraph(_run('Exercitation ullamco'), style: 'Heading3'),
  _paragraph(_run('Duis aute irure dolor in reprehenderit.'), style: 'Quote'),
  '<w:tbl><w:tblPr><w:tblW w:w="8640" w:type="dxa"/>'
      '<w:tblBorders><w:top w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/>'
      '<w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders>'
      '</w:tblPr><w:tblGrid><w:gridCol w:w="4320"/><w:gridCol w:w="4320"/></w:tblGrid>'
      '${_row(['Lorem', 'Ipsum'], header: true)}'
      '${_row(['Dolor', 'Sit amet'])}${_row(['Consectetur', 'Adipiscing'])}</w:tbl>',
  _paragraph(_run(_lorem)),
  '<w:sectPr/>',
].join();

String _change(String kind, int id, String author, String date, String inner) =>
    '<w:$kind w:id="$id" w:author="$author" w:date="$date">$inner</w:$kind>';

final _revisions = [
  _paragraph(_run('Revisions'), style: 'Heading1'),
  _paragraph(
    [
      _run('Lorem ipsum dolor sit amet, '),
      _change(
        'ins',
        1,
        'Ann Author',
        '2026-01-02T10:00:00Z',
        _run('consectetur adipiscing elit, '),
      ),
      _change(
        'del',
        2,
        'Bob Editor',
        '2026-01-03T11:30:00Z',
        '<w:r><w:delText xml:space="preserve">sed do eiusmod tempor, </w:delText></w:r>',
      ),
      '<w:r><w:rPr><w:b/>'
          '${_change('rPrChange', 3, 'Ann Author', '2026-01-04T12:00:00Z', '<w:rPr/>')}'
          '</w:rPr><w:t xml:space="preserve">incididunt ut labore</w:t></w:r>',
      _run(' et dolore magna aliqua.'),
    ].join(),
  ),
  _paragraph(_run(_lorem)),
  '<w:sectPr/>',
].join();

/// Size in half-points, as Word gives it.
String _sized(int half, {bool bold = false}) =>
    '${bold ? '<w:b/>' : ''}<w:sz w:val="$half"/>';

final _degenerate = [
  _paragraph(_run('Lorem Ipsum Dolor', _sized(32, bold: true))),
  _paragraph(_run(_lorem, _sized(24))),
  _paragraph(_run('Sit Amet Consectetur', _sized(32, bold: true))),
  _paragraph(_run(_lorem, _sized(24))),
  _paragraph(
    _run('Mixed: ', _sized(24)) +
        _run('larger', _sized(36)) +
        _run(' and smaller.', _sized(24)),
  ),
  '<w:sectPr/>',
].join();

/// [parts] zipped into [file], with every entry dated [_date] and in the
/// order given, `[Content_Types].xml` first.
void _zip(File file, Map<String, String> parts) {
  final staging = Directory.systemTemp.createTempSync('rtf_samples');
  try {
    for (final MapEntry(key: path, value: content) in parts.entries) {
      final part = File('${staging.path}/$path')..createSync(recursive: true);
      part
        ..writeAsStringSync(content)
        ..setLastModifiedSync(_date);
    }
    if (file.existsSync()) {
      file.deleteSync();
    }
    _command('/usr/bin/zip', [
      '-X',
      '-q',
      file.absolute.path,
      ...parts.keys,
    ], directory: staging.path);
  } finally {
    staging.deleteSync(recursive: true);
  }
}
