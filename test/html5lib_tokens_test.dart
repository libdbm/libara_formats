import 'dart:convert';
import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:libara_formats/src/html/html.dart' show doctype, selfClosed;
import 'package:test/test.dart';

import 'harness.dart';

/// The html5lib tokenizer tests: the tokens each input reads as, against
/// layer 2's, read back as the stream of tokens the standard's tokenizer
/// emits. Parse errors are not compared.
///
/// Left out: tests starting in a state other than data, or naming the last
/// start tag, since layer 2 is read without context. Skipped, with the
/// reason: tests whose stream reads markup inside an element HTML reads as
/// text, which is one token here with its content.
void main() {
  const html = HTML();
  for (final file
      in Directory('test/html5lib/tokenizer')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.test'))
          .toList()
        ..sort((one, other) => one.path.compareTo(other.path))) {
    final name = file.uri.pathSegments.last;
    final tests =
        (jsonDecode(file.readAsStringSync()) as Map)['tests'] as List? ?? [];
    for (final (number, raw) in tests.indexed) {
      final kase = raw as Map;
      final states = (kase['initialStates'] as List?) ?? ['Data state'];
      if (!states.contains('Data state') || kase.containsKey('lastStartTag')) {
        continue;
      }
      final escaped = kase['doubleEscaped'] == true;
      String unescape(String text) => escaped
          ? text.replaceAllMapped(
              RegExp(r'\\u([0-9A-Fa-f]{4})'),
              (match) => String.fromCharCode(int.parse(match[1]!, radix: 16)),
            )
          : text;
      final input = unescape(kase['input'] as String);
      final expected = _merged([
        for (final token in kase['output'] as List)
          [
            for (final part in token as List)
              part is String
                  ? unescape(part)
                  : part is Map
                  ? {
                      for (final MapEntry(:key, :value) in part.entries)
                        unescape(key as String): unescape(value as String),
                    }
                  : part,
          ],
      ]);
      final read = _stream(decoded(html, input));
      test(
        '$name #$number ${kase['description']}',
        () {
          expect(jsonEncode(read), jsonEncode(expected), reason: input);
        },
        skip: read == null
            ? 'markup inside an element HTML reads as text is one token here'
            : false,
      );
    }
  }
}

/// [document]'s layer 2 as the standard's tokenizer emits it, or null
/// where an element HTML reads as text holds markup, which its one token
/// cannot say.
List<Object?>? _stream(Layered<int> document) {
  final stream = <List<Object?>>[];
  for (final range in document.layer(2).items.cast<ARange>()) {
    final name = '${range.get('')}';
    final text = string(document.slice(range));
    switch (name) {
      case '#text':
        stream.add(['Character', _lines(text)]);
      case '#entity':
        stream.add(['Character', '${range.get('shows')}']);
      case '#bogus':
        break;
      case '#doctype':
        final (:name, :public, :system, :correct) = doctype(text);
        stream.add([
          'DOCTYPE',
          name,
          public == null ? null : _lines(public),
          system == null ? null : _lines(system),
          correct,
        ]);
      case '#comment':
        stream.add(['Comment', _lines(_comment(text))]);
      case '#cdata':
        stream.add(['Comment', _lines(_comment(text))]);
      case '#pi':
        final body = text.substring(2, text.length - 1);
        final cut = body.indexOf(RegExp(r'[\t\n\f\r ?>]'));
        final target = cut < 0 ? body : body.substring(0, cut);
        var data = body.substring(target.length).trimLeft();
        if (data.endsWith('?')) {
          data = data.substring(0, data.length - 1);
        }
        stream.add(['ProcessingInstruction', target, _lines(data)]);
      default:
        if (text.startsWith('</')) {
          stream.add(['EndTag', name]);
          continue;
        }
        final close = _close(text);
        final tag = [
          'StartTag',
          name,
          {
            for (final MapEntry(:key, :value) in range.attributes.entries)
              if (key.isNotEmpty) key: _lines('$value'),
          },
          if (selfClosed(text.substring(0, close + 1))) true,
        ];
        stream.add(tag);
        if (close + 1 < text.length) {
          final rest = text.substring(close + 1);
          final end = rest.toLowerCase().lastIndexOf('</$name');
          final content = end < 0 ? rest : rest.substring(0, end);
          if (content.contains('<') || content.contains('&')) {
            return null;
          }
          if (content.isNotEmpty) {
            stream.add(['Character', _lines(content)]);
          }
          if (end >= 0) {
            stream.add(['EndTag', name]);
          }
        }
    }
  }
  return _merged(stream);
}

/// The index of the `>` closing the start tag at the head of [text].
int _close(String text) {
  var quote = '';
  for (var at = 1; at < text.length; at++) {
    final unit = text[at];
    if (quote.isNotEmpty) {
      if (unit == quote) {
        quote = '';
      }
    } else if (unit == '"' || unit == "'") {
      quote = unit;
    } else if (unit == '>') {
      return at;
    }
  }
  return text.length - 1;
}

/// What a comment token [text] says, as the standard's tokenizer reads it:
/// a comment by its comment states, and a bogus comment as what follows
/// its `<!` or `</`, or its `<` before a `?`, to its `>`.
String _comment(String text) {
  if (!text.startsWith('<!--')) {
    // What follows `<!` or `</`; a `<?` keeps its question mark.
    final from = text.startsWith('<?') ? 1 : 2;
    final body = text.endsWith('>')
        ? text.substring(from, text.length - 1)
        : text.substring(from);
    return body.replaceAll('\u0000', '\uFFFD');
  }
  final data = StringBuffer();
  var state = 'start';
  for (final unit in text.substring(4).runes) {
    final character = String.fromCharCode(unit == 0 ? 0xFFFD : unit);
    switch (state) {
      case 'start' || 'dash' when unit == 0x3E:
        return data.toString();
      case 'start' when unit == 0x2D:
        state = 'dash';
      case 'dash' when unit == 0x2D:
        state = 'end';
      case 'dash':
        data.write('-$character');
        state = 'comment';
      case 'start' || 'comment' when unit == 0x2D:
        state = 'ending';
      case 'start' || 'comment':
        data.write(character);
        state = 'comment';
      case 'ending' when unit == 0x2D:
        state = 'end';
      case 'ending':
        data.write('-$character');
        state = 'comment';
      case 'end' when unit == 0x3E:
        return data.toString();
      case 'end' when unit == 0x21:
        state = 'bang';
      case 'end' when unit == 0x2D:
        data.write('-');
      case 'end':
        data.write('--$character');
        state = 'comment';
      case 'bang' when unit == 0x2D:
        data.write('--!');
        state = 'ending';
      case 'bang' when unit == 0x3E:
        return data.toString();
      case 'bang':
        data.write('--!$character');
        state = 'comment';
    }
  }
  return data.toString();
}

/// [text] with its line ends made line feeds, as the standard's input
/// stream makes them.
String _lines(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// [stream] with each run of character tokens made one.
List<Object?> _merged(List<List<Object?>> stream) {
  final merged = <List<Object?>>[];
  for (final token in stream) {
    if (token.first == 'Character' &&
        merged.isNotEmpty &&
        merged.last.first == 'Character') {
      merged.last[1] = '${merged.last[1]}${token[1]}';
    } else {
      merged.add([...token]);
    }
  }
  return merged;
}
