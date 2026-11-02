/// RTF's tokens, each read from where it starts without looking back.
library;

import '../lexing.dart';
import 'pages.dart';

/// The longest control word RTF allows, and the longest parameter.
const _letters = 32;
const _digits = 10;

/// What a control word shows, where it shows anything.
const Map<String, String> _words = {
  'par': '\n',
  'line': '\n',
  'tab': '\t',
  'emdash': '\u2014',
  'endash': '\u2013',
  'lquote': '\u2018',
  'rquote': '\u2019',
  'ldblquote': '\u201C',
  'rdblquote': '\u201D',
  'bullet': '\u2022',
  'emspace': '\u2003',
  'enspace': '\u2002',
  'qmspace': '\u2005',
};

/// What a control symbol shows: `\~` a no-break space, `\_` a
/// non-breaking hyphen, an escaped mark itself, and `\-` and `\*` nothing.
const Map<int, String> _symbols = {
  0x5C: r'\',
  0x7B: '{',
  0x7D: '}',
  0x7E: '\u00A0',
  0x5F: '\u2011',
  0x2D: '',
  0x2A: '',
  0x3A: ':',
};

/// The scanner for RTF whose bytes past 127 are in [page].
Scanner scanner(Page page) =>
    (text, at) => _next(text, at, page);

Token _next(String text, int at, Page page) {
  final code = text.codeUnitAt(at);
  if (code == 0x7B || code == 0x7D) {
    return (at + 1, String.fromCharCode(code), const {}, null);
  }
  if (code == 0x0D || code == 0x0A) {
    var end = at + 1;
    while (end < text.length && _broken(text.codeUnitAt(end))) {
      end++;
    }
    return (end, '#break', const {}, null);
  }
  if (code == 0x5C) {
    return _control(text, at, page);
  }
  if (code > 0xFF) {
    return (at + 1, '#error', const {}, 'an item past 255 is not a byte');
  }
  if (code > 0x7F) {
    return (
      at + 1,
      '#character',
      {'shows': literal(String.fromCharCode(page.shows(code)))},
      null,
    );
  }
  var end = at + 1;
  while (end < text.length && _plain(text.codeUnitAt(end))) {
    end++;
  }
  return (end, prose, const {}, null);
}

bool _broken(int code) => code == 0x0D || code == 0x0A;

/// Whether [code] carries on a run of text.
bool _plain(int code) =>
    code <= 0x7F &&
    code != 0x5C &&
    code != 0x7B &&
    code != 0x7D &&
    !_broken(code);

bool _letter(int code) =>
    code >= 0x61 && code <= 0x7A || code >= 0x41 && code <= 0x5A;

bool _digit(int code) => code >= 0x30 && code <= 0x39;

/// The control word, symbol or escape whose backslash is at [at].
Token _control(String text, int at, Page page) {
  if (at + 1 >= text.length) {
    return (at + 1, '#error', const {}, 'a backslash ends the text');
  }
  final code = text.codeUnitAt(at + 1);
  if (_broken(code)) {
    // A backslash before a line break is a paragraph mark, as Cocoa writes
    // one.
    var end = at + 2;
    if (code == 0x0D && end < text.length && text.codeUnitAt(end) == 0x0A) {
      end++;
    }
    return (end, 'par', {'shows': literal('\n')}, null);
  }
  if (code == 0x27) {
    return _escape(text, at, page);
  }
  if (!_letter(code)) {
    final shows = _symbols[code];
    return (
      at + 2,
      '#symbol',
      {
        'symbol': literal(String.fromCharCode(code)),
        if (shows != null && shows.isNotEmpty) 'shows': literal(shows),
      },
      shows == null ? 'an unknown control symbol' : null,
    );
  }
  var end = at + 1;
  while (end < text.length && _letter(text.codeUnitAt(end))) {
    end++;
  }
  final word = text.substring(at + 1, end);
  if (word.length > _letters) {
    return (end, '#error', const {}, 'a control word past $_letters letters');
  }
  final start = end;
  if (end < text.length && text.codeUnitAt(end) == 0x2D) {
    end++;
  }
  while (end < text.length && _digit(text.codeUnitAt(end))) {
    end++;
  }
  final digits = text.substring(start, end);
  if (digits.length > _digits + 1) {
    return (end, '#error', const {}, 'a parameter past $_digits digits');
  }
  final value = digits == '-' ? null : int.tryParse(digits);
  if (digits == '-') {
    end = start;
  }
  if (end < text.length && text.codeUnitAt(end) == 0x20) {
    end++;
  }
  if (word == 'bin' && value != null) {
    return _binary(text, end, value);
  }
  if (word == 'u' && value != null) {
    return _unicode(text, end, value);
  }
  return (
    end,
    word,
    {
      'value': ?value == null ? null : literal('$value'),
      'shows': ?_words[word] == null ? null : literal(_words[word]!),
    },
    null,
  );
}

/// `\'hh`, from [at]: the byte it is, shown through [page].
Token _escape(String text, int at, Page page) {
  final end = at + 4;
  final digits = end <= text.length ? text.substring(at + 2, end) : '';
  final byte = RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(digits)
      ? int.parse(digits, radix: 16)
      : null;
  if (byte == null) {
    return (
      at + 2,
      '#error',
      const {},
      "\\' is not followed by two hexadecimal digits",
    );
  }
  return (
    end,
    '#escape',
    {'shows': literal(String.fromCharCode(page.shows(byte)))},
    null,
  );
}

/// `\binN`, its data from [at]: the [count] bytes it says follow.
Token _binary(String text, int at, int count) {
  final end = at + count;
  if (count < 0 || end > text.length) {
    return (
      text.length,
      'bin',
      {'value': literal('$count')},
      '\\bin says $count bytes follow, and ${text.length - at} do',
    );
  }
  return (end, 'bin', {'value': literal('$count')}, null);
}

/// `\uN`, from just past it at [at]: the character [value] is, as a signed
/// 16-bit number, and the fallback that follows it where it is `?` or one
/// `\'hh`. A high surrogate followed by `\u` and a low one is the character
/// they make together.
Token _unicode(String text, int at, int value) {
  int unit(int value) => value < 0 ? value + 0x10000 : value;
  int fallback(int at) {
    if (at < text.length && text.codeUnitAt(at) == 0x3F) {
      return at + 1;
    }
    if (at + 3 < text.length && text.startsWith(r"\'", at)) {
      return at + 4;
    }
    return at;
  }

  final high = unit(value);
  var end = fallback(at);
  if (high < 0 || high > 0xFFFF) {
    return (end, '#unicode', const {}, '\\u$value is not a character');
  }
  if (high >= 0xD800 && high <= 0xDBFF) {
    final low = RegExp(r'\\u(-?\d{1,6}) ?').matchAsPrefix(text, end);
    final second = low == null ? null : unit(int.parse(low[1]!));
    if (low != null && second! >= 0xDC00 && second <= 0xDFFF) {
      final point = 0x10000 + ((high - 0xD800) << 10) + (second - 0xDC00);
      end = fallback(low.end);
      return (
        end,
        '#unicode',
        {'shows': literal(String.fromCharCode(point))},
        null,
      );
    }
  }
  if (high >= 0xD800 && high <= 0xDFFF) {
    return (end, '#unicode', {'shows': literal('\uFFFD')}, 'a lone surrogate');
  }
  return (end, '#unicode', {'shows': literal(String.fromCharCode(high))}, null);
}
