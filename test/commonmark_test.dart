import 'dart:convert';
import 'dart:io';

import 'package:libara/libara.dart';
import 'package:libara_formats/libara_formats.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// What Markdown makes of the CommonMark suite, ported from markwrite's
/// `commonmark_test`: the structure read from each example is written out
/// as HTML, by a renderer that is the test's own, and set against the HTML
/// the example must come to.
///
/// The renderer also does what markwrite marked as hidden tokens and this
/// syntax derives instead: the spaces at a line's edges and the return
/// before a newline are layout, and a line ending in a code span is a
/// space. Only runs of `#text` are so read, so a space a reference represents
/// is kept.

/// The examples markwrite passes at `62b585b`, 567 of 652.
const passing = [
  1,
  2,
  3,
  4,
  8,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  32,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  40,
  41,
  42,
  43,
  44,
  45,
  46,
  47,
  48,
  49,
  50,
  51,
  52,
  53,
  54,
  55,
  56,
  57,
  58,
  59,
  60,
  61,
  62,
  63,
  64,
  65,
  66,
  67,
  68,
  69,
  70,
  71,
  72,
  73,
  74,
  75,
  76,
  77,
  78,
  79,
  80,
  81,
  82,
  83,
  84,
  85,
  86,
  87,
  88,
  89,
  90,
  91,
  92,
  93,
  94,
  95,
  96,
  97,
  98,
  99,
  100,
  101,
  102,
  103,
  104,
  105,
  106,
  107,
  108,
  109,
  110,
  111,
  112,
  113,
  114,
  115,
  116,
  117,
  118,
  119,
  120,
  121,
  122,
  123,
  124,
  125,
  126,
  127,
  128,
  129,
  130,
  131,
  132,
  133,
  134,
  135,
  136,
  137,
  138,
  139,
  140,
  141,
  142,
  143,
  144,
  145,
  146,
  147,
  192,
  193,
  194,
  195,
  196,
  197,
  198,
  199,
  200,
  202,
  203,
  204,
  205,
  206,
  207,
  208,
  209,
  210,
  211,
  212,
  213,
  214,
  217,
  218,
  219,
  220,
  221,
  222,
  223,
  224,
  225,
  226,
  227,
  228,
  229,
  230,
  231,
  232,
  233,
  234,
  235,
  237,
  238,
  239,
  240,
  241,
  242,
  243,
  244,
  245,
  246,
  247,
  248,
  249,
  250,
  251,
  253,
  254,
  255,
  256,
  257,
  258,
  259,
  260,
  261,
  262,
  263,
  264,
  265,
  266,
  267,
  268,
  269,
  270,
  271,
  272,
  273,
  274,
  275,
  276,
  277,
  278,
  279,
  280,
  281,
  282,
  283,
  284,
  285,
  286,
  287,
  288,
  289,
  290,
  291,
  292,
  293,
  294,
  295,
  296,
  297,
  298,
  299,
  301,
  302,
  303,
  304,
  305,
  306,
  307,
  310,
  311,
  312,
  314,
  315,
  316,
  317,
  319,
  321,
  322,
  323,
  324,
  325,
  326,
  327,
  328,
  329,
  330,
  331,
  332,
  333,
  334,
  335,
  336,
  337,
  338,
  339,
  340,
  341,
  342,
  343,
  345,
  346,
  347,
  348,
  349,
  350,
  351,
  352,
  353,
  354,
  355,
  356,
  357,
  358,
  359,
  360,
  361,
  362,
  363,
  364,
  365,
  366,
  367,
  368,
  369,
  370,
  371,
  372,
  373,
  374,
  375,
  376,
  377,
  378,
  379,
  380,
  381,
  382,
  383,
  384,
  385,
  386,
  387,
  388,
  389,
  390,
  391,
  392,
  393,
  394,
  395,
  396,
  397,
  398,
  399,
  400,
  401,
  402,
  403,
  404,
  405,
  406,
  407,
  408,
  409,
  410,
  411,
  412,
  413,
  414,
  415,
  416,
  417,
  418,
  419,
  420,
  421,
  422,
  423,
  424,
  425,
  426,
  427,
  428,
  429,
  430,
  431,
  432,
  433,
  434,
  435,
  436,
  437,
  438,
  439,
  440,
  441,
  442,
  443,
  444,
  445,
  446,
  447,
  448,
  449,
  450,
  451,
  452,
  453,
  454,
  455,
  456,
  457,
  458,
  459,
  460,
  461,
  462,
  463,
  464,
  465,
  466,
  467,
  468,
  469,
  470,
  471,
  472,
  473,
  474,
  478,
  479,
  480,
  481,
  482,
  483,
  484,
  485,
  486,
  487,
  488,
  489,
  490,
  492,
  493,
  495,
  496,
  497,
  498,
  499,
  500,
  501,
  502,
  503,
  504,
  505,
  506,
  507,
  508,
  509,
  510,
  511,
  512,
  513,
  514,
  515,
  516,
  517,
  518,
  519,
  520,
  521,
  522,
  523,
  525,
  526,
  527,
  528,
  529,
  530,
  531,
  532,
  533,
  534,
  535,
  537,
  538,
  539,
  541,
  542,
  543,
  544,
  545,
  546,
  547,
  548,
  549,
  550,
  551,
  552,
  553,
  554,
  555,
  556,
  557,
  558,
  559,
  560,
  561,
  562,
  563,
  564,
  565,
  566,
  567,
  568,
  569,
  570,
  571,
  572,
  573,
  574,
  575,
  576,
  577,
  578,
  579,
  580,
  581,
  582,
  583,
  584,
  585,
  586,
  587,
  588,
  589,
  590,
  591,
  592,
  593,
  594,
  595,
  596,
  597,
  598,
  599,
  600,
  601,
  602,
  603,
  604,
  605,
  606,
  607,
  608,
  609,
  610,
  611,
  612,
  618,
  619,
  620,
  621,
  622,
  624,
  632,
  633,
  634,
  635,
  636,
  637,
  638,
  639,
  640,
  641,
  644,
  645,
  646,
  647,
  648,
  649,
  650,
  651,
  652,
];

/// One example of the suite.
typedef Example = ({int number, String section, String source, String html});

List<Example> suite() => [
  for (final one in jsonDecode(
    File('test/commonmark/spec.json').readAsStringSync(),
  ) as List<Object?>)
    if (one case final Map<String, Object?> one)
      (
        number: one['example'] as int,
        section: one['section'] as String,
        source: one['markdown'] as String,
        html: one['html'] as String,
      ),
];

/// The elements a document is built of, as against the ones a line is.
const blocks = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol', 'li', //
  'pre', 'hr', 'table', 'tr', 'td', 'th',
};

/// One element and what stands inside it, over token indices.
final class Node {
  Node(this.element, this.start, this.end);

  final ARange? element;
  final int start;
  final int end;
  final List<Node> children = [];
}

/// How far out an element stands where two cover the same tokens.
int holding(String name) => switch (name) {
  'ul' || 'ol' => 0,
  'li' => 1,
  _ when blocks.contains(name) => 2,
  _ => 3,
};

/// The renderer over one document.
final class Rendering {
  Rendering(this.document)
    : tokens = document.layer(2).items.cast<ARange>().toList();

  final Layered<int> document;
  final List<ARange> tokens;

  /// The elements, nested: one holds another that stands within it.
  Node tree() {
    final held = document.layer(3).items.cast<ARange>().toList()
      ..sort((one, other) {
        final at = one.start.compareTo(other.start);
        if (at != 0) {
          return at;
        }
        final wide = other.length.compareTo(one.length);
        return wide != 0
            ? wide
            : holding('${one.get('')}').compareTo(holding('${other.get('')}'));
      });
    final root = Node(null, 0, tokens.length);
    final open = [root];
    for (final element in held) {
      while (open.length > 1 && element.start >= open.last.end) {
        open.removeLast();
      }
      final node = Node(element, element.start, element.end);
      open.last.children.add(node);
      open.add(node);
    }
    return root;
  }

  /// What tokens [from] to [to] say to a reader: text as it is, less the
  /// layout at a line's edges, a reference or an escape what it shows, and
  /// markup nothing.
  String said(int from, int to, {bool code = false, bool raw = false}) {
    final out = StringBuffer();
    var head = !raw && headed(from);
    for (var at = from; at < to; at++) {
      final token = tokens[at];
      final name = '${token.get('')}';
      if (name == '#entity' || name == '#escape') {
        out.write(token.get('shows'));
        head = false;
        continue;
      }
      if (name != '#text') {
        continue;
      }
      var text = string(document.slice(token));
      if (code) {
        text = text.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
      } else if (!raw) {
        text = text
            .replaceAll('\r\n', '\n')
            .replaceAll(RegExp('[ \t]+\n'), '\n')
            .replaceAll(RegExp('\n[ \t]+'), '\n');
        if (head) {
          text = text.replaceFirst(RegExp('^[ \t]+'), '');
        }
      }
      if (text.isNotEmpty) {
        head = text.endsWith('\n');
      }
      out.write(text);
    }
    return out.toString();
  }

  /// Whether token [at] stands at a line's head: first, or after a line
  /// ending or a block's own marker.
  bool headed(int at) {
    if (at == 0) {
      return true;
    }
    final before = tokens[at - 1];
    final name = '${before.get('')}';
    return string(document.slice(before)).endsWith('\n') ||
        blocks.contains(name) ||
        RegExp(r'^h[1-6]$').hasMatch(name);
  }

  /// [node]'s children as the HTML the suite asks for.
  String written(Node node, {bool code = false}) {
    final held = node.children.any(
      (child) => blocks.contains('${child.element!.get('')}'),
    );
    final out = StringBuffer();
    var at = node.start;
    void words(int to) {
      final said = escaped(this.said(at, to, code: code));
      out.write(held ? said.trim() : said);
      if (held && said.trim().isNotEmpty) {
        out.write('\n');
      }
    }

    for (final child in node.children) {
      if (child.start > at) {
        words(child.start);
      }
      out.write(tagged(child));
      at = child.end;
    }
    if (at < node.end) {
      final said = escaped(this.said(at, node.end, code: code));
      out.write(held ? said.trim() : said);
    }
    return out.toString();
  }

  String tagged(Node node) {
    final element = node.element!;
    final name = '${element.get('')}';
    final attributes = StringBuffer();
    for (final key in const ['href', 'src', 'alt', 'title', 'class', 'start']) {
      if (element.get(key) case final value?) {
        attributes.write(' $key="${escaped('$value')}"');
      }
    }
    switch (name) {
      case 'hr':
        return '<hr />\n';
      case 'br':
        return '<br />';
      case 'img':
        return '<img$attributes />';
      case 'pre':
        final said = this
            .said(node.start, node.end, raw: true)
            .replaceAll(RegExp(r'\n*$'), '');
        final ends = said.isEmpty ? '' : '\n';
        return '<pre><code$attributes>${escaped(said)}$ends</code></pre>\n';
    }
    final inner = written(node, code: name == 'code');
    if (!blocks.contains(name)) {
      return '<$name$attributes>$inner</$name>';
    }
    final nested = node.children.any(
      (child) => blocks.contains('${child.element!.get('')}'),
    );
    final said = nested
        ? (inner.startsWith('<') ? '\n${inner.trim()}\n' : '${inner.trim()}\n')
        : trimmed(inner);
    if (said.trim().isEmpty) {
      if (name == 'li') {
        return '<$name$attributes></$name>\n';
      }
      if (name == 'blockquote') {
        return '<$name$attributes>\n</$name>\n';
      }
    }
    return '<$name$attributes>$said</$name>\n';
  }
}

/// [held] with the layout at its end taken off.
String trimmed(String held) {
  var at = held.length;
  while (at > 0 && ' \t\n\r'.contains(held[at - 1])) {
    at -= 1;
  }
  return held.substring(0, at);
}

String escaped(String held) => held
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// What [source] comes to, as HTML.
String rendered(String source) {
  final rendering = Rendering(decoded(const Markdown(), source));
  return rendering.written(rendering.tree());
}

void main() {
  final examples = suite();

  test('the suite is the one it says it is', () {
    expect(examples, hasLength(652));
  });

  test('every example markwrite passes passes here', () {
    final passed = {
      for (final example in examples)
        if (rendered(example.source).trim() == example.html.trim())
          example.number,
    };
    // ignore: avoid_print
    print('CommonMark 0.31.2: ${passed.length} of ${examples.length}');
    final lost = [
      for (final number in passing)
        if (!passed.contains(number)) number,
    ];
    expect(lost, isEmpty, reason: 'passing on markwrite and not here');
  });
}
