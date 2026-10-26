part of 'html.dart';

/// HTML's layer 3: the WHATWG tree construction run over layer 2's tokens.
///
/// The builder keeps a tree and does to it what the standard does, the
/// adoption agency's moves included. Each element owns its own tags, and
/// each token read while it is the current node and taken by nothing else:
/// text, comments, ignored tags. Its range runs from the first token it or
/// anything under it owns to the last, and an element owning none is empty
/// where it was made. Content keeps its order in the text throughout, so
/// every range holds exactly what the element holds. Ranges can tie or be
/// empty, so how they nest is read from the tree: see [nested].
///
/// Followed: every insertion mode but those of foreign content, with the
/// adoption agency as the standard has it now and select as it has been
/// read since 2025. A template's content is its element's children here,
/// the separate fragment the standard keeps being a DOM detail ranges need
/// not show. Not followed: foster parenting. Content the standard would
/// move to before a table stays where it is written, inside the table,
/// under a diagnostic saying it was fostered.
final class _Builder {
  _Builder(this.document, {this.deepest})
    : tokens = document.layer(2).items.cast<ARange>().toList(),
      _text = document.items.items.toList();

  final Layered<int> document;

  /// Layer 2's tokens.
  final List<ARange> tokens;

  /// The text, read once, since reading the document's text one token at
  /// a time costs most of a build.
  final List<int> _text;

  /// The most elements that may stand open at once, or null for any.
  final int? deepest;

  final problems = <ARange>[];
  final _root = _Node('#document', 0, const {});
  final _open = _Stack();

  /// The list of active formatting elements, null standing for a marker.
  final _active = <_Node?>[];

  /// The stack of template insertion modes.
  final _templates = <_Mode>[];
  var _mode = _Mode.initial;

  /// The mode to go back to from a table's text.
  _Node? _form;

  /// The head element pointer.
  _Node? _pointer;

  /// Whether the document is in quirks mode, which its doctype decides.
  var _quirks = false;

  /// The frameset-ok flag.
  var _framed = true;

  /// The index in layer 2 of the token being read.
  var _index = 0;

  /// The elements found open at the end that the standard objects to, and
  /// where among the problems that is said.
  var _unclosed = (at: 0, nodes: const <_Node>[]);

  /// Whether the token being read has been given to an element.
  var _placed = false;

  /// Whether the token being read is one the standard would foster out of
  /// a table.
  var _fostering = false;

  /// The elements, in pre-order, each with its depth below the document
  /// and its namespace, `svg`, `math` or empty for HTML; and the parse
  /// errors.
  (List<(ARange, int, String)>, List<ARange>) run() {
    for (var at = 0; at < tokens.length; at++) {
      _index = at;
      _placed = false;
      final token = _read(tokens[at]);
      while (!_step(token)) {}
      if (!_placed) {
        _current.kids.add(_index);
      }
      if (deepest case final most? when _open.highest > most) {
        problems.add(limited(span(at, 1), 'elements nested deeper than $most'));
        break;
      }
    }
    _index = tokens.length;
    _end();
    // What each element reaches is read once the tree is built, since it
    // is read once for all and kept.
    problems.insertAll(_unclosed.at, [
      for (final node in _unclosed.nodes)
        if (node.reach() case (final low, _))
          ranged(low, low < tokens.length ? 1 : 0, {
            'message': literal('unclosed <${node.name}>'),
          }),
    ]);
    final elements = <(ARange, int, String)>[];
    void walk(_Node node, int depth) {
      for (final kid in node.kids) {
        if (kid is _Node) {
          final (low, high) = kid.reach();
          elements.add((
            ranged(low, high - low, kid.attributes),
            depth,
            kid.space,
          ));
          walk(kid, depth + 1);
        }
      }
    }

    walk(_root, 0);
    return (elements, problems);
  }

  /// The text of [range], one of [tokens] or within them.
  String _covered(Range range) =>
      String.fromCharCodes(_text, range.start, range.end);

  _Node get _current => _open.isEmpty ? _root : _open.last;

  /// What the standard makes of [range], a layer-2 token.
  _Token _read(ARange range) {
    final name = '${range.get('')}';
    switch (name) {
      case '#text':
        final text = _covered(range);
        return _Token(
          text.trim().isEmpty ? _Kind.space : _Kind.text,
          name,
          range: range,
          // A NUL is ignored in body, so text of nothing else says nothing.
          said: text.replaceAll('\u0000', '').trim().isNotEmpty,
        );
      case '#entity':
        return _Token(
          '${range.get('shows')}'.trim().isEmpty ? _Kind.space : _Kind.text,
          name,
          range: range,
        );
      case '#cdata':
        return _Token(_Kind.cdata, name, range: range);
      case '#comment' || '#pi':
        return const _Token(_Kind.comment, '#comment');
      case '#doctype':
        return _Token(_Kind.doctype, '#doctype', range: range);
      case '#bogus':
        return const _Token(_Kind.skip, '#bogus');
    }
    final closing = _text[range.start + 1] == _slash;
    // The standard reads an image start tag as img.
    final called = !closing && name == 'image' ? 'img' : name;
    return _Token(
      closing ? _Kind.end : _Kind.start,
      called,
      attributes: called == name
          ? range.attributes
          : {...range.attributes, '': literal(called)},
      whole: !closing && (_raw.contains(name) || name == 'plaintext'),
      range: range,
      closed: !closing && selfClosed(_covered(range)),
    );
  }

  /// Reads [token] in the current insertion mode, and says whether it was
  /// taken, or is to be read again in the mode it moved to.
  bool _step(_Token token) {
    if (token.kind == _Kind.skip) {
      return true;
    }
    if (_foreigned(token)) {
      return _foreign(token);
    }
    // A CDATA section outside foreign content is the bogus comment the
    // standard makes of it.
    return _moded(
      token.kind == _Kind.cdata
          ? const _Token(_Kind.comment, '#comment')
          : token,
    );
  }

  /// Whether [token] is read by the rules for foreign content rather than
  /// those of the insertion mode.
  bool _foreigned(_Token token) {
    final node = _current;
    if (_open.isEmpty || node.space.isEmpty) {
      return false;
    }
    final character = const {
      _Kind.space,
      _Kind.text,
      _Kind.cdata,
    }.contains(token.kind);
    final start = token.kind == _Kind.start;
    if (node.texting &&
        ((start && token.name != 'mglyph' && token.name != 'malignmark') ||
            character)) {
      return false;
    }
    if (node.space == 'math' &&
        node.name == 'annotation-xml' &&
        start &&
        token.name == 'svg') {
      return false;
    }
    if (node.integrating && (start || character)) {
      return false;
    }
    return true;
  }

  /// The rules for parsing tokens in foreign content.
  bool _foreign(_Token token) {
    final name = token.name;
    switch (token.kind) {
      case _Kind.space || _Kind.text || _Kind.cdata:
        if (token.said && token.kind != _Kind.space) {
          _framed = false;
        }
        return true;
      case _Kind.comment || _Kind.doctype || _Kind.skip:
        return true;
      case _Kind.start:
        if (_breaking.contains(name) ||
            (name == 'font' &&
                const {
                  'color',
                  'face',
                  'size',
                }.any(token.attributes.containsKey))) {
          _problem('<$name> in foreign content');
          _breakOut();
          return false;
        }
        final space = _current.space;
        final called = space == 'svg' ? (_svgNames[name] ?? name) : name;
        final node =
            _Node(called, _index, {...token.attributes, '': literal(called)})
              ..space = space
              ..own.add(_index);
        _foster(node);
        _current.adopt(node);
        _open.add(node);
        _placed = true;
        if (token.closed || token.whole) {
          _open.removeLast();
        }
        return true;
      case _Kind.end:
        if (name == 'br' || name == 'p') {
          _problem('</$name> in foreign content');
          _breakOut();
          return false;
        }
        var at = _open.length - 1;
        var node = _open[at];
        if (node.name.toLowerCase() != name) {
          _problem('end tag </$name> closes nothing open');
        }
        while (true) {
          if (at == 0) {
            return true;
          }
          if (node.name.toLowerCase() == name) {
            while (_open.removeLast() != node) {}
            node.own.add(_index);
            _placed = true;
            return true;
          }
          at--;
          node = _open[at];
          if (node.space.isEmpty) {
            return _moded(token);
          }
        }
    }
  }

  /// Pops what foreign content stands open, back to an integration point
  /// or an HTML element.
  void _breakOut() {
    while (!(_current.texting ||
        _current.integrating ||
        _current.space.isEmpty)) {
      _open.removeLast();
    }
  }

  /// Reads [token] by the rules of the current insertion mode.
  bool _moded(_Token token) => switch (_mode) {
    _Mode.initial => _initial(token),
    _Mode.html => _html(token),
    _Mode.head => _head(token),
    _Mode.inHead => _inHead(token),
    _Mode.afterHead => _afterHead(token),
    _Mode.body => _body(token),
    _Mode.table => _table(token),
    _Mode.caption => _caption(token),
    _Mode.columns => _columns(token),
    _Mode.rows => _rows(token),
    _Mode.row => _row(token),
    _Mode.cell => _cell(token),
    _Mode.template => _template(token),
    _Mode.afterBody => _afterBody(token),
    _Mode.frameset => _frameset(token),
    _Mode.afterFrameset => _afterFrameset(token),
    _Mode.afterAfterBody => _afterAfterBody(token),
    _Mode.afterAfterFrameset => _afterAfterFrameset(token),
  };

  bool _initial(_Token token) {
    switch (token.kind) {
      case _Kind.space || _Kind.comment:
        return true;
      case _Kind.doctype:
        _quirks = _quirky(_covered(token.range!));
        _mode = _Mode.html;
        return true;
      default:
        _quirks = true;
        _mode = _Mode.html;
        return false;
    }
  }

  bool _html(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.space || _Kind.comment || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        _insert(token);
        _mode = _Mode.head;
        return true;
      case _Token(kind: _Kind.end, :final name)
          when !const {'head', 'body', 'html', 'br'}.contains(name):
        return _stray(token);
      default:
        _imply('html');
        _mode = _Mode.head;
        return false;
    }
  }

  bool _head(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.space || _Kind.comment || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.start, name: 'head'):
        _pointer = _insert(token);
        _mode = _Mode.inHead;
        return true;
      case _Token(kind: _Kind.end, :final name)
          when !const {'head', 'body', 'html', 'br'}.contains(name):
        return _stray(token);
      default:
        _pointer = _imply('head');
        _mode = _Mode.inHead;
        return false;
    }
  }

  bool _inHead(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.space || _Kind.comment || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.start, :final name)
          when _headed.contains(name) || _headRaw.contains(name):
        _single(token);
        return true;
      case _Token(kind: _Kind.start, name: 'template'):
        _insert(token);
        _active.add(null);
        _framed = false;
        _mode = _Mode.template;
        _templates.add(_Mode.template);
        return true;
      case _Token(kind: _Kind.end, name: 'template'):
        if (!_templated) {
          return _stray(token);
        }
        _thorough();
        _until('template', own: true);
        _clear();
        _templates.removeLast();
        _reset();
        return true;
      case _Token(kind: _Kind.start, name: 'head'):
        return true;
      case _Token(kind: _Kind.end, name: 'head'):
        _pop(own: true);
        _mode = _Mode.afterHead;
        return true;
      case _Token(kind: _Kind.end, :final name)
          when !const {'body', 'html', 'br'}.contains(name):
        return _stray(token);
      default:
        _pop();
        _mode = _Mode.afterHead;
        return false;
    }
  }

  bool _afterHead(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.space || _Kind.comment || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.start, name: 'body'):
        _insert(token);
        _framed = false;
        _mode = _Mode.body;
        return true;
      case _Token(kind: _Kind.start, name: 'frameset'):
        _insert(token);
        _mode = _Mode.frameset;
        return true;
      case _Token(kind: _Kind.start, :final name)
          when _headed.contains(name) ||
              name == 'template' ||
              (_headRaw.contains(name) && name != 'noscript'):
        // The standard puts it back into the head. Since the head closed only
        // space, comments and ignored tags can have come, so the head's range
        // reaches it without crossing anything.
        _problem('misplaced <$name>');
        final head = _pointer!;
        _open.add(head);
        _inHead(token);
        _open.remove(head);
        return true;
      case _Token(kind: _Kind.end, name: 'template'):
        return _inHead(token);
      case _Token(kind: _Kind.start, name: 'head'):
        return true;
      case _Token(kind: _Kind.end, :final name)
          when !const {'body', 'html', 'br'}.contains(name):
        return _stray(token);
      default:
        _imply('body');
        _framed = true;
        _mode = _Mode.body;
        return false;
    }
  }

  bool _body(_Token token) {
    final name = token.name;
    switch (token.kind) {
      case _Kind.space:
        _reconstruct();
        return true;
      case _Kind.text:
        _reconstruct();
        if (token.said) {
          _framed = false;
        }
        return true;
      case _Kind.comment || _Kind.cdata || _Kind.doctype || _Kind.skip:
        return true;
      case _Kind.start:
        return _start(token);
      case _Kind.end:
        if (name == 'body' || name == 'html') {
          if (_scoped('body')) {
            _mode = _Mode.afterBody;
            return name == 'body';
          }
          return _stray(token);
        }
        if (name == 'template') {
          return _inHead(token);
        }
        _close(token);
        return true;
    }
  }

  /// A start tag in body, and whether it was taken.
  bool _start(_Token token) {
    final name = token.name;
    if (name == 'a') {
      if (_formatting('a') case final held?) {
        _problem('<a> inside <a>');
        _adopt('a');
        _open.remove(held);
        _active.remove(held);
      }
      _reconstruct();
      _format(token);
    } else if (_formats.contains(name)) {
      _reconstruct();
      _format(token);
    } else if (name == 'nobr') {
      _reconstruct();
      if (_scoped('nobr')) {
        _problem('<nobr> inside <nobr>');
        _adopt('nobr');
        _reconstruct();
      }
      _format(token);
    } else if (const {'applet', 'marquee', 'object'}.contains(name)) {
      _reconstruct();
      _insert(token);
      _active.add(null);
      _framed = false;
    } else if (name == 'html') {
      return true;
    } else if (name == 'body') {
      if (_open.length > 1 && _open[1].name == 'body' && !_templated) {
        _framed = false;
      }
    } else if (name == 'frameset') {
      if (_open.length > 1 && _open[1].name == 'body' && _framed) {
        final body = _open[1];
        body.parent?.kids.remove(body);
        while (_open.length > 1) {
          _open.removeLast();
        }
        _insert(token);
        _mode = _Mode.frameset;
      }
    } else if (_headed.contains(name) ||
        _headRaw.contains(name) && name != 'noscript' ||
        name == 'template') {
      return _inHead(token);
    } else if (name == 'svg' || name == 'math') {
      _reconstruct();
      final node = _Node(name, _index, token.attributes)
        ..space = name
        ..own.add(_index);
      _foster(node);
      _current.adopt(node);
      _placed = true;
      if (!token.closed) {
        _open.add(node);
      }
    } else if (name == 'select') {
      if (_scoped('select')) {
        _problem('<select> inside <select>');
        _until('select');
      } else {
        _reconstruct();
        _insert(token);
        _framed = false;
      }
    } else if (name == 'option') {
      if (_scoped('select')) {
        _implied(except: 'optgroup');
        if (_scoped('option')) {
          _problem('<option> inside <option>');
        }
      } else if (_current.name == 'option') {
        _pop();
      }
      _reconstruct();
      _insert(token);
    } else if (name == 'optgroup') {
      if (_scoped('select')) {
        _implied();
        if (_scoped('option') || _scoped('optgroup')) {
          _problem('<optgroup> inside <option> or <optgroup>');
        }
      } else if (_current.name == 'option') {
        _pop();
      }
      _reconstruct();
      _insert(token);
    } else if (token.whole) {
      if (const {'xmp', 'plaintext'}.contains(name)) {
        _closeP();
      }
      if (name == 'xmp') {
        _reconstruct();
      }
      _framed = false;
      if (name == 'plaintext') {
        _plaintext(token);
        return true;
      }
      _single(token);
    } else if (_ignored.contains(name)) {
      return true;
    } else if (name == 'table') {
      if (!_quirks) {
        _closeP();
      }
      _insert(token);
      _framed = false;
      _mode = _Mode.table;
    } else if (_blocks.contains(name)) {
      _closeP();
      if (const {'pre', 'listing'}.contains(name)) {
        _framed = false;
      }
      _insert(token);
    } else if (_headings.contains(name)) {
      _closeP();
      if (_headings.contains(_current.name)) {
        _problem('a heading inside a heading');
        _pop();
      }
      _insert(token);
    } else if (name == 'form') {
      if (_form != null && !_templated) {
        return true;
      }
      _closeP();
      final form = _insert(token);
      if (!_templated) {
        _form = form;
      }
    } else if (name == 'li') {
      _framed = false;
      _listed(const {'li'});
      _closeP();
      _insert(token);
    } else if (name == 'dd' || name == 'dt') {
      _framed = false;
      _listed(const {'dd', 'dt'});
      _closeP();
      _insert(token);
    } else if (name == 'button') {
      if (_scoped('button')) {
        _implied();
        _until('button');
      }
      _reconstruct();
      _insert(token);
      _framed = false;
    } else if (name == 'hr') {
      _closeP();
      if (_scoped('select')) {
        _implied();
        if (_scoped('option') || _scoped('optgroup')) {
          _problem('<hr> inside <option> or <optgroup>');
        }
      }
      _single(token);
      _framed = false;
    } else if (name == 'input') {
      if (_scoped('select')) {
        _problem('<input> inside <select>');
        _until('select');
      }
      _reconstruct();
      _single(token);
      if (!_hidden(token)) {
        _framed = false;
      }
    } else if (_voids.contains(name)) {
      if (!const {'param', 'source', 'track'}.contains(name)) {
        _reconstruct();
        _framed = false;
      }
      _single(token);
    } else if (name == 'rb' || name == 'rtc') {
      if (_scoped('ruby')) {
        _implied();
      }
      _insert(token);
    } else if (name == 'rp' || name == 'rt') {
      if (_scoped('ruby')) {
        _implied(except: 'rtc');
      }
      _insert(token);
    } else {
      _reconstruct();
      _insert(token);
    }
    return true;
  }

  /// A plaintext element. Unlike the other elements whose content is not
  /// markup, the standard reads its text in body, reopening the active
  /// formatting elements inside it; those clones hold no token of their
  /// own, the text being the plaintext's one token, so they are empty.
  void _plaintext(_Token token) {
    final node = _insert(token);
    if (_holdsText(token.range!)) {
      _reconstruct();
    }
    while (_open.last != node) {
      _open.removeLast();
    }
  }

  /// Whether the whole-element token [range] holds anything past its start
  /// tag.
  bool _holdsText(ARange range) {
    final text = _covered(range);
    final close = text.indexOf('>');
    return close >= 0 && close + 1 < text.length;
  }

  /// Whether the input [token] starts is hidden.
  bool _hidden(_Token token) =>
      '${token.attributes['type']}'.toLowerCase() == 'hidden';

  /// An end tag in body other than `body`, `html` and `template`.
  void _close(_Token token) {
    final name = token.name;
    if (_formats.contains(name) || name == 'a' || name == 'nobr') {
      _adopt(name);
    } else if (const {'applet', 'marquee', 'object'}.contains(name)) {
      if (!_scoped(name)) {
        _stray(token);
        return;
      }
      _implied();
      _until(name, own: true);
      _clear();
    } else if (name == 'p') {
      if (!_scoped('p', _button)) {
        _problem('end tag </p> with no p open');
        _imply('p');
      }
      _implied(except: 'p');
      _until('p', own: true);
    } else if (name == 'br') {
      _problem('end tag </br> read as <br>');
      _start(_Token(_Kind.start, 'br', attributes: {'': literal('br')}));
    } else if (name == 'form') {
      if (_templated) {
        if (!_scoped('form')) {
          _stray(token);
          return;
        }
        _implied();
        _until('form', own: true);
        return;
      }
      // The form leaves the stack and nothing else does: what is open inside
      // it stays open, and what comes next goes into that, inside the form.
      final form = _form;
      _form = null;
      if (form == null || !_scopedNode(form)) {
        _stray(token);
        return;
      }
      _implied();
      _open.remove(form);
      form.own.add(_index);
      _placed = true;
    } else if (name == 'li') {
      if (!_scoped('li', _listing)) {
        _stray(token);
        return;
      }
      _implied(except: 'li');
      _until('li', own: true);
    } else if (name == 'dd' || name == 'dt') {
      if (!_scoped(name)) {
        _stray(token);
        return;
      }
      _implied(except: name);
      _until(name, own: true);
    } else if (_headings.contains(name)) {
      if (!_headings.any(_scoped)) {
        _stray(token);
        return;
      }
      _implied();
      while (true) {
        final node = _open.last;
        _pop(own: node.name == name);
        if (_headings.contains(node.name)) {
          break;
        }
      }
    } else if (_blocks.contains(name) || name == 'button' || name == 'select') {
      if (!_scoped(name)) {
        _stray(token);
        return;
      }
      _implied();
      _until(name, own: true);
    } else {
      _other(name);
    }
  }

  /// An end tag closing the nearest open element of [name], unless a
  /// special element stands nearer.
  void _other(String name) {
    for (var at = _open.length - 1; at >= 0; at--) {
      final node = _open[at];
      if (node.name == name) {
        _implied(except: name);
        _until(name, own: true);
        return;
      }
      if (node.special) {
        _problem('end tag </$name> closes nothing');
        return;
      }
    }
  }

  /// In table.
  bool _table(_Token token) {
    final name = token.name;
    switch (token.kind) {
      case _Kind.space when _tabular.contains(_current.name):
        return true;
      case _Kind.comment || _Kind.doctype:
        return true;
      case _Kind.start:
        switch (name) {
          case 'caption':
            _back(_tableContext);
            _active.add(null);
            _insert(token);
            _mode = _Mode.caption;
            return true;
          case 'colgroup':
            _back(_tableContext);
            _insert(token);
            _mode = _Mode.columns;
            return true;
          case 'col':
            _back(_tableContext);
            _imply('colgroup');
            _mode = _Mode.columns;
            return false;
          case 'tbody' || 'tfoot' || 'thead':
            _back(_tableContext);
            _insert(token);
            _mode = _Mode.rows;
            return true;
          case 'td' || 'th' || 'tr':
            _back(_tableContext);
            _imply('tbody');
            _mode = _Mode.rows;
            return false;
          case 'table':
            _problem('<table> inside <table>');
            if (!_tabled('table')) {
              return true;
            }
            _until('table');
            _reset();
            return false;
          case 'style' || 'script' || 'template':
            return _inHead(token);
          case 'input' when _hidden(token):
            _problem('<input> in a table');
            _single(token);
            return true;
          case 'form':
            _problem('<form> in a table');
            if (_form != null && !_templated) {
              return true;
            }
            final form = _insert(token);
            _open.removeLast();
            if (!_templated) {
              _form = form;
            }
            return true;
        }
      case _Kind.end:
        switch (name) {
          case 'table':
            if (!_tabled('table')) {
              return _stray(token);
            }
            _until('table', own: true);
            _reset();
            return true;
          case 'body' ||
              'caption' ||
              'col' ||
              'colgroup' ||
              'html' ||
              'tbody' ||
              'td' ||
              'tfoot' ||
              'th' ||
              'thead' ||
              'tr':
            return _stray(token);
          case 'template':
            return _inHead(token);
        }
      default:
    }
    return _fostered(token);
  }

  /// A token the standard would foster out of a table, read in body where
  /// it stands: what it inserts while a table part is the current node
  /// stays there, under a diagnostic.
  bool _fostered(_Token token) {
    _fostering = true;
    if (token.kind == _Kind.text && _tabular.contains(_current.name)) {
      _problem('fostered text');
    }
    final taken = _body(token);
    _fostering = false;
    return taken;
  }

  /// Says so where [node] is inserted where the standard would foster it.
  void _foster(_Node node) {
    if (_fostering && _tabular.contains(_current.name)) {
      _problem('fostered <${node.name}>');
    }
  }

  /// In caption.
  bool _caption(_Token token) {
    final name = token.name;
    final closing =
        (token.kind == _Kind.end && (name == 'caption' || name == 'table')) ||
        (token.kind == _Kind.start && _tableParts.contains(name));
    if (closing) {
      if (!_tabled('caption')) {
        return _stray(token);
      }
      _implied();
      _until('caption', own: token.kind == _Kind.end && name == 'caption');
      _clear();
      _mode = _Mode.table;
      return token.kind == _Kind.end && name == 'caption';
    }
    if (token.kind == _Kind.end &&
        const {
          'body', 'col', 'colgroup', 'html', 'tbody', 'td', 'tfoot', 'th', //
          'thead', 'tr',
        }.contains(name)) {
      return _stray(token);
    }
    return _body(token);
  }

  /// In column group.
  bool _columns(_Token token) {
    final name = token.name;
    switch (token) {
      case _Token(kind: _Kind.space || _Kind.comment || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.start, name: 'col'):
        _single(token);
        return true;
      case _Token(kind: _Kind.end, name: 'colgroup'):
        if (_current.name != 'colgroup') {
          return _stray(token);
        }
        _pop(own: true);
        _mode = _Mode.table;
        return true;
      case _Token(kind: _Kind.end, name: 'col'):
        return _stray(token);
      case _Token(kind: _Kind.start || _Kind.end, name: 'template'):
        return _inHead(token);
    }
    if (_current.name != 'colgroup') {
      _problem(
        '${name.startsWith('#') ? 'text' : '<$name>'} in a column group',
      );
      return true;
    }
    _pop();
    _mode = _Mode.table;
    return false;
  }

  /// In table body.
  bool _rows(_Token token) {
    final name = token.name;
    if (token.kind == _Kind.start && name == 'tr') {
      _back(_bodyContext);
      _insert(token);
      _mode = _Mode.row;
      return true;
    }
    if (token.kind == _Kind.start && (name == 'th' || name == 'td')) {
      _problem('<$name> outside a row');
      _back(_bodyContext);
      _imply('tr');
      _mode = _Mode.row;
      return false;
    }
    if (token.kind == _Kind.end && _sections.contains(name)) {
      if (!_tabled(name)) {
        return _stray(token);
      }
      _back(_bodyContext);
      _pop(own: true);
      _mode = _Mode.table;
      return true;
    }
    if ((token.kind == _Kind.start &&
            const {
              'caption', 'col', 'colgroup', 'tbody', 'tfoot', 'thead', //
            }.contains(name)) ||
        (token.kind == _Kind.end && name == 'table')) {
      if (!_sections.any(_tabled)) {
        return _stray(token);
      }
      _back(_bodyContext);
      _pop();
      _mode = _Mode.table;
      return false;
    }
    if (token.kind == _Kind.end &&
        const {
          'body', 'caption', 'col', 'colgroup', 'html', 'td', 'th', 'tr', //
        }.contains(name)) {
      return _stray(token);
    }
    return _table(token);
  }

  /// In row.
  bool _row(_Token token) {
    final name = token.name;
    if (token.kind == _Kind.start && (name == 'th' || name == 'td')) {
      _back(_rowContext);
      _insert(token);
      _mode = _Mode.cell;
      _active.add(null);
      return true;
    }
    if (token.kind == _Kind.end && name == 'tr') {
      if (!_tabled('tr')) {
        return _stray(token);
      }
      _back(_rowContext);
      _pop(own: true);
      _mode = _Mode.rows;
      return true;
    }
    if ((token.kind == _Kind.start &&
            const {
              'caption', 'col', 'colgroup', 'tbody', 'tfoot', 'thead', 'tr', //
            }.contains(name)) ||
        (token.kind == _Kind.end && name == 'table')) {
      if (!_tabled('tr')) {
        return _stray(token);
      }
      _back(_rowContext);
      _pop();
      _mode = _Mode.rows;
      return false;
    }
    if (token.kind == _Kind.end && _sections.contains(name)) {
      if (!_tabled(name) || !_tabled('tr')) {
        return _stray(token);
      }
      _back(_rowContext);
      _pop();
      _mode = _Mode.rows;
      return false;
    }
    if (token.kind == _Kind.end &&
        const {
          'body', 'caption', 'col', 'colgroup', 'html', 'td', 'th', //
        }.contains(name)) {
      return _stray(token);
    }
    return _table(token);
  }

  /// In cell.
  bool _cell(_Token token) {
    final name = token.name;
    if (token.kind == _Kind.end && (name == 'td' || name == 'th')) {
      if (!_tabled(name)) {
        return _stray(token);
      }
      _implied();
      _until(name, own: true);
      _clear();
      _mode = _Mode.row;
      return true;
    }
    if (token.kind == _Kind.start && _tableParts.contains(name)) {
      if (!_tabled('td') && !_tabled('th')) {
        return _stray(token);
      }
      _shut();
      return false;
    }
    if (token.kind == _Kind.end &&
        const {'body', 'caption', 'col', 'colgroup', 'html'}.contains(name)) {
      return _stray(token);
    }
    if (token.kind == _Kind.end &&
        const {'table', 'tbody', 'tfoot', 'thead', 'tr'}.contains(name)) {
      if (!_tabled(name)) {
        return _stray(token);
      }
      _shut();
      return false;
    }
    return _body(token);
  }

  /// Closes the open cell.
  void _shut() {
    _implied();
    while (true) {
      final node = _open.removeLast();
      if (node.name == 'td' || node.name == 'th') {
        break;
      }
    }
    _clear();
    _mode = _Mode.row;
  }

  /// In template.
  bool _template(_Token token) {
    final name = token.name;
    switch (token.kind) {
      case _Kind.space ||
          _Kind.text ||
          _Kind.cdata ||
          _Kind.comment ||
          _Kind.doctype:
        return _body(token);
      case _Kind.start:
        if (_headed.contains(name) ||
            const {
              'noframes', 'script', 'style', 'template', 'title', //
            }.contains(name)) {
          return _inHead(token);
        }
        final next = switch (name) {
          'caption' ||
          'colgroup' ||
          'tbody' ||
          'tfoot' ||
          'thead' => _Mode.table,
          'col' => _Mode.columns,
          'tr' => _Mode.rows,
          'td' || 'th' => _Mode.row,
          _ => _Mode.body,
        };
        _templates
          ..removeLast()
          ..add(next);
        _mode = next;
        return false;
      case _Kind.end:
        if (name == 'template') {
          return _inHead(token);
        }
        return _stray(token);
      case _Kind.skip:
        return true;
    }
  }

  /// In frameset.
  bool _frameset(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.space || _Kind.comment || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.start, name: 'frameset'):
        _insert(token);
        return true;
      case _Token(kind: _Kind.end, name: 'frameset'):
        if (_current.name == 'html') {
          return _stray(token);
        }
        _pop(own: true);
        if (_current.name != 'frameset') {
          _mode = _Mode.afterFrameset;
        }
        return true;
      case _Token(kind: _Kind.start, name: 'frame'):
        _single(token);
        return true;
      case _Token(kind: _Kind.start, name: 'noframes'):
        return _inHead(token);
      default:
        _problem('content in a frameset');
        return true;
    }
  }

  /// After frameset.
  bool _afterFrameset(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.space || _Kind.comment || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.end, name: 'html'):
        _mode = _Mode.afterAfterFrameset;
        return true;
      case _Token(kind: _Kind.start, name: 'noframes'):
        return _inHead(token);
      default:
        _problem('content after a frameset');
        return true;
    }
  }

  /// After after frameset.
  bool _afterAfterFrameset(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.comment):
        _root.kids.add(_index);
        _placed = true;
        return true;
      case _Token(kind: _Kind.space || _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.start, name: 'noframes'):
        return _inHead(token);
      default:
        _problem('content after a frameset');
        return true;
    }
  }

  /// Resets the insertion mode appropriately, from what stands open.
  void _reset() {
    for (var at = _open.length - 1; at >= 0; at--) {
      final node = _open[at];
      final last = at == 0;
      if (node.space.isNotEmpty && !last) {
        continue;
      }
      switch (node.name) {
        case 'td' || 'th' when !last:
          _mode = _Mode.cell;
          return;
        case 'tr':
          _mode = _Mode.row;
          return;
        case 'tbody' || 'thead' || 'tfoot':
          _mode = _Mode.rows;
          return;
        case 'caption':
          _mode = _Mode.caption;
          return;
        case 'colgroup':
          _mode = _Mode.columns;
          return;
        case 'table':
          _mode = _Mode.table;
          return;
        case 'template':
          _mode = _templates.last;
          return;
        case 'head' when !last:
          _mode = _Mode.inHead;
          return;
        case 'body':
          _mode = _Mode.body;
          return;
        case 'frameset':
          _mode = _Mode.frameset;
          return;
        case 'html':
          _mode = _pointer == null ? _Mode.head : _Mode.afterHead;
          return;
      }
      if (last) {
        _mode = _Mode.body;
        return;
      }
    }
  }

  /// Pops until the current node is one of [context], clearing the stack
  /// back to a table, table body or row context.
  void _back(Set<String> context) {
    while (!context.contains(_current.name)) {
      _open.removeLast();
    }
  }

  /// Whether a template is open.
  bool get _templated =>
      _open.holds('template') &&
      _open.any((node) => node.name == 'template' && node.space.isEmpty);

  /// Generates every implied end tag, thoroughly.
  void _thorough() {
    while (_open.isNotEmpty && _thoroughly.contains(_current.name)) {
      _pop();
    }
  }

  /// The adoption agency, for an end tag of the formatting element [name],
  /// as the standard has it now.
  void _adopt(String name) {
    final current = _current;
    if (current.name == name && !_active.contains(current)) {
      _pop(own: true);
      return;
    }
    for (var outer = 0; outer < 8; outer++) {
      final element = _formatting(name);
      if (element == null) {
        _other(name);
        return;
      }
      if (!_open.contains(element)) {
        _problem('end tag </$name> closes nothing open');
        _active.remove(element);
        return;
      }
      if (!_scopedNode(element)) {
        _problem('end tag </$name> closes nothing in scope');
        return;
      }
      if (element != _current) {
        _problem('end tag </$name> closes elements opened inside it');
      }
      final at = _open.indexOf(element);
      _Node? furthest;
      for (final node in _open.skip(at + 1)) {
        if (node.special) {
          furthest = node;
          break;
        }
      }
      if (furthest == null) {
        while (true) {
          final node = _open.removeLast();
          if (node == element) {
            node.own.add(_index);
            _placed = true;
            break;
          }
        }
        _active.remove(element);
        return;
      }
      final common = _open[at - 1];
      var bookmark = _active.indexOf(element);
      var last = furthest;
      var node = furthest;
      var index = _open.indexOf(node);
      for (var inner = 1; ; inner++) {
        index--;
        node = _open[index];
        if (node == element) {
          break;
        }
        if (inner > 3 && _active.contains(node)) {
          final held = _active.indexOf(node);
          _active.removeAt(held);
          if (held < bookmark) {
            bookmark--;
          }
        }
        if (!_active.contains(node)) {
          _open.removeAt(index);
          continue;
        }
        final clone = node.copy(_index);
        _active[_active.indexOf(node)] = clone;
        _open[index] = clone;
        node = clone;
        if (last == furthest) {
          bookmark = _active.indexOf(clone) + 1;
        }
        node.adopt(last);
        last = node;
      }
      common.adopt(last);
      final clone = element.copy(_index);
      clone.take(furthest);
      furthest.adopt(clone);
      final held = _active.indexOf(element);
      _active.removeAt(held);
      if (held < bookmark) {
        bookmark--;
      }
      _active.insert(min(bookmark, _active.length), clone);
      _open.remove(element);
      _open.insert(_open.indexOf(furthest) + 1, clone);
    }
  }

  /// The last element of [name] in the list of active formatting elements
  /// after its last marker.
  _Node? _formatting(String name) {
    for (final node in _active.reversed) {
      if (node == null) {
        return null;
      }
      if (node.name == name) {
        return node;
      }
    }
    return null;
  }

  /// Inserts the formatting element [token] starts and adds it to the list
  /// of active formatting elements, which holds no more than three alike
  /// after its last marker: the earliest goes.
  void _format(_Token token) {
    final node = _insert(token);
    final alike = <_Node>[];
    for (final held in _active.reversed) {
      if (held == null) {
        break;
      }
      if (held.name == node.name && same(held.attributes, node.attributes)) {
        alike.add(held);
      }
    }
    if (alike.length >= 3) {
      _active.remove(alike.last);
    }
    _active.add(node);
  }

  /// Reopens the active formatting elements that are no longer open, as
  /// clones made here, in their order.
  void _reconstruct() {
    if (_active.isEmpty) {
      return;
    }
    var at = _active.length - 1;
    var entry = _active[at];
    if (entry == null || _open.contains(entry)) {
      return;
    }
    while (entry != null && !_open.contains(entry)) {
      if (at == 0) {
        at = -1;
        break;
      }
      at--;
      entry = _active[at];
    }
    while (true) {
      at++;
      final clone = _active[at]!.copy(_index);
      _foster(clone);
      _current.adopt(clone);
      _open.add(clone);
      _active[at] = clone;
      if (at == _active.length - 1) {
        return;
      }
    }
  }

  /// Clears the list of active formatting elements up to its last marker.
  void _clear() {
    while (_active.isNotEmpty && _active.removeLast() != null) {}
  }

  /// Whether [element] is in scope.
  bool _scopedNode(_Node element) {
    for (var at = _open.length - 1; at >= 0; at--) {
      final node = _open[at];
      if (node == element) {
        return true;
      }
      if (node.bounding) {
        return false;
      }
    }
    return false;
  }

  bool _afterBody(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.comment):
        _open.first.kids.add(_index);
        _placed = true;
        return true;
      case _Token(kind: _Kind.space):
        return _body(token);
      case _Token(kind: _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      case _Token(kind: _Kind.end, name: 'html'):
        _mode = _Mode.afterAfterBody;
        return true;
      default:
        _problem('content after the body');
        _mode = _Mode.body;
        return false;
    }
  }

  bool _afterAfterBody(_Token token) {
    switch (token) {
      case _Token(kind: _Kind.comment):
        _root.kids.add(_index);
        _placed = true;
        return true;
      case _Token(kind: _Kind.space):
        return _body(token);
      case _Token(kind: _Kind.doctype):
        return true;
      case _Token(kind: _Kind.start, name: 'html'):
        return true;
      default:
        _problem('content after the document');
        _mode = _Mode.body;
        return false;
    }
  }

  /// The end of the text: what the standard objects to finding open, and
  /// every open element closed there.
  void _end() {
    _unclosed = (
      at: problems.length,
      nodes: [
        for (final node in _open)
          if (!_closable.contains(node.name)) node,
      ],
    );
    while (_templates.isNotEmpty && _templated) {
      _until('template');
      _clear();
      _templates.removeLast();
      _reset();
    }
    if (_mode == _Mode.initial) {
      _quirks = true;
      _mode = _Mode.html;
    }
    if (_mode == _Mode.html) {
      _imply('html');
      _mode = _Mode.head;
    }
    if (_mode == _Mode.head) {
      _pointer = _imply('head');
      _mode = _Mode.inHead;
    }
    if (_mode == _Mode.inHead) {
      while (_open.last.name != 'html') {
        _pop();
      }
      _mode = _Mode.afterHead;
    }
    if (_mode == _Mode.afterHead) {
      _imply('body');
    }
    while (_open.isNotEmpty) {
      _pop();
    }
  }

  /// Inserts and pushes the element [token] starts.
  _Node _insert(_Token token) {
    final node = _Node(token.name, _index, token.attributes)..own.add(_index);
    _foster(node);
    _current.adopt(node);
    _open.add(node);
    _placed = true;
    return node;
  }

  /// Inserts and pushes the element called [name] that the standard implies
  /// here.
  _Node _imply(String name) {
    final node = _Node(name, _index, {'': literal(name)});
    _foster(node);
    _current.adopt(node);
    _open.add(node);
    return node;
  }

  /// Inserts the element [token] is all of: a void element, or one whose
  /// content is not markup.
  void _single(_Token token) {
    final node = _Node(token.name, _index, token.attributes)..own.add(_index);
    _foster(node);
    _current.adopt(node);
    _placed = true;
  }

  /// Pops the current node, giving it the token being read where that is
  /// its [own] end tag.
  void _pop({bool own = false}) {
    final node = _open.removeLast();
    if (own) {
      node.own.add(_index);
      _placed = true;
    }
  }

  /// Pops until the element called [name] is popped, it by its [own] end
  /// tag where that is the token being read.
  void _until(String name, {bool own = false}) {
    while (true) {
      final node = _open.last;
      final found = node.name == name && node.space.isEmpty;
      _pop(own: own && found);
      if (found) {
        return;
      }
    }
  }

  /// Generates the implied end tags, but for [except].
  void _implied({String? except}) {
    while (_open.isNotEmpty &&
        _implying.contains(_current.name) &&
        _current.name != except) {
      _pop();
    }
  }

  /// Closes a `p` in button scope, as a block's start tag does.
  void _closeP() {
    if (_scoped('p', _button)) {
      _implied(except: 'p');
      _until('p');
    }
  }

  /// Closes the open item of [names] that a new one ends, as `li`, `dd` and
  /// `dt` do.
  void _listed(Set<String> names) {
    for (var at = _open.length - 1; at >= 0; at--) {
      final node = _open[at];
      if (names.contains(node.name)) {
        _implied(except: node.name);
        _until(node.name);
        return;
      }
      if (node.special && !const {'address', 'div', 'p'}.contains(node.name)) {
        return;
      }
    }
  }

  /// Whether an element called [name] is in table scope, which only
  /// `html`, `table` and `template` bound.
  bool _tabled(String name) {
    for (var at = _open.length - 1; at >= 0; at--) {
      final node = _open[at].name;
      if (node == name) {
        return true;
      }
      if (_tableScope.contains(node)) {
        return false;
      }
    }
    return false;
  }

  /// Whether an element called [name] is in scope, the elements of [extra]
  /// bounding it as well as the scope's own.
  bool _scoped(String name, [Set<String> extra = const {}]) {
    if (!_open.holds(name)) {
      return false;
    }
    for (var at = _open.length - 1; at >= 0; at--) {
      final node = _open[at];
      if (node.name == name && node.space.isEmpty) {
        return true;
      }
      if (node.bounding || (node.space.isEmpty && extra.contains(node.name))) {
        return false;
      }
    }
    return false;
  }

  /// An end tag that closes nothing, which the standard ignores.
  bool _stray(_Token token) {
    _problem('end tag </${token.name}> closes nothing');
    return true;
  }

  void _problem(String message) {
    problems.add(ranged(_index, 1, {'message': literal(message)}));
  }
}

enum _Mode {
  initial,
  html,
  head,
  inHead,
  afterHead,
  body,
  table,
  caption,
  columns,
  rows,
  row,
  cell,
  template,
  afterBody,
  frameset,
  afterFrameset,
  afterAfterBody,
  afterAfterFrameset,
}

enum _Kind { space, text, cdata, comment, doctype, start, end, skip }

/// A layer-2 token as tree construction reads it.
final class _Token {
  const _Token(
    this.kind,
    this.name, {
    this.attributes = const {},
    this.whole = false,
    this.range,
    this.said = true,
    this.closed = false,
  });

  final _Kind kind;
  final String name;
  final Map<String, Value> attributes;

  /// Whether this start tag is a whole element, its content and end tag
  /// with it.
  final bool whole;

  /// The layer-2 token read, where what it covers matters.
  final ARange? range;

  /// Whether this text says something besides space and NULs, which body
  /// ignores.
  final bool said;

  /// Whether this start tag closes itself, which counts in foreign
  /// content.
  final bool closed;
}

/// The stack of open elements, which knows in constant time whether it
/// holds a node, and whether it holds any node of a name.
final class _Stack extends Iterable<_Node> {
  final _nodes = <_Node>[];
  final _held = Set<_Node>.identity();
  final _names = <String, int>{};

  /// The most nodes it has held at once.
  var highest = 0;

  @override
  Iterator<_Node> get iterator => _nodes.iterator;

  @override
  int get length => _nodes.length;

  @override
  bool get isEmpty => _nodes.isEmpty;

  @override
  bool get isNotEmpty => _nodes.isNotEmpty;

  @override
  _Node get first => _nodes.first;

  @override
  _Node get last => _nodes.last;

  @override
  bool contains(Object? element) => _held.contains(element);

  /// Whether a node called [name] is open, in any namespace.
  bool holds(String name) => (_names[name] ?? 0) > 0;

  _Node operator [](int index) => _nodes[index];

  void operator []=(int index, _Node node) {
    _forget(_nodes[index]);
    _nodes[index] = node;
    _held.add(node);
    _names[node.name] = (_names[node.name] ?? 0) + 1;
  }

  int indexOf(_Node node) => _nodes.indexOf(node);

  void add(_Node node) => insert(_nodes.length, node);

  void insert(int index, _Node node) {
    _nodes.insert(index, node);
    _held.add(node);
    _names[node.name] = (_names[node.name] ?? 0) + 1;
    if (_nodes.length > highest) {
      highest = _nodes.length;
    }
  }

  _Node removeLast() => _forget(_nodes.removeLast());

  _Node removeAt(int index) => _forget(_nodes.removeAt(index));

  bool remove(_Node node) {
    final index = _nodes.indexOf(node);
    if (index < 0) {
      return false;
    }
    removeAt(index);
    return true;
  }

  _Node _forget(_Node node) {
    _held.remove(node);
    _names[node.name] = _names[node.name]! - 1;
    return node;
  }
}

/// An element of the tree being built.
final class _Node {
  _Node(this.name, this.made, this.attributes);

  final String name;

  /// The index in layer 2 of the token being read when it was made.
  final int made;

  final Map<String, Value> attributes;

  /// Its namespace: `svg`, `math`, or empty for HTML.
  var space = '';

  /// Whether it is a MathML text integration point.
  bool get texting =>
      space == 'math' && const {'mi', 'mo', 'mn', 'ms', 'mtext'}.contains(name);

  /// Whether it is an HTML integration point.
  bool get integrating => switch (space) {
    'svg' => const {'foreignObject', 'desc', 'title'}.contains(name),
    'math' =>
      name == 'annotation-xml' &&
          const {
            'text/html',
            'application/xhtml+xml',
          }.contains('${attributes['encoding']}'.toLowerCase()),
    _ => false,
  };

  /// Whether it bounds an element's scope.
  bool get bounding => switch (space) {
    '' => _scope.contains(name),
    'math' => const {
      'mi', 'mo', 'mn', 'ms', 'mtext', 'annotation-xml', //
    }.contains(name),
    _ => const {'foreignObject', 'desc', 'title'}.contains(name),
  };

  /// Whether it is in the standard's special category.
  bool get special => space.isEmpty ? _special.contains(name) : bounding;

  /// The indices of its own tags.
  final own = <int>[];

  /// Its children: elements, and the indices of the tokens it holds.
  final kids = <Object>[];

  _Node? parent;

  /// [node] moved to be its last child.
  void adopt(_Node node) {
    node.parent?.kids.remove(node);
    node.parent = this;
    kids.add(node);
  }

  /// The children of [node] moved to be its own.
  void take(_Node node) {
    for (final kid in node.kids) {
      if (kid is _Node) {
        kid.parent = this;
      }
    }
    kids.addAll(node.kids);
    node.kids.clear();
  }

  /// A clone, made at token [at], with no tags of its own.
  _Node copy(int at) => _Node(name, at, attributes)..space = space;

  /// The first token it or anything under it owns, and one past the last,
  /// or an empty reach where it was made where there is none; read once
  /// the tree is built, and kept.
  (int, int) reach() => _reach ??= _reached();

  (int, int)? _reach;

  (int, int) _reached() {
    var low = -1;
    var high = -1;
    void see(int at) {
      if (low < 0 || at < low) {
        low = at;
      }
      if (at + 1 > high) {
        high = at + 1;
      }
    }

    own.forEach(see);
    for (final kid in kids) {
      if (kid is int) {
        see(kid);
      } else {
        final (from, to) = (kid as _Node).reach();
        if (to > from) {
          see(from);
          see(to - 1);
        }
      }
    }
    return low < 0 ? (made, made) : (low, high);
  }
}

/// Layer 3's elements in pre-order, each with its depth below the
/// document, as the tree construction nests them.
///
/// Ranges can tie: an implied element and what it holds can cover the same
/// tokens, and so can the clones the standard makes of formatting elements.
/// Which holds which is the tree's to say, so it is read from the tree,
/// built again, rather than stored.
List<(ARange, int, String)> nested(Layered<int> document) =>
    _Builder(document).run().$1;

/// The start tags that break out of foreign content.
const _breaking = {
  'b', 'big', 'blockquote', 'body', 'br', 'center', 'code', 'dd', 'div', //
  'dl', 'dt', 'em', 'embed', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head', 'hr',
  'i', 'img', 'li', 'listing', 'menu', 'meta', 'nobr', 'ol', 'p', 'pre',
  'ruby', 's', 'small', 'span', 'strong', 'strike', 'sub', 'sup', 'table',
  'tt', 'u', 'ul', 'var',
};

/// SVG element names as written, from the lower case a tag is read in.
const _svgNames = {
  'altglyph': 'altGlyph', 'altglyphdef': 'altGlyphDef', //
  'altglyphitem': 'altGlyphItem', 'animatecolor': 'animateColor',
  'animatemotion': 'animateMotion', 'animatetransform': 'animateTransform',
  'clippath': 'clipPath', 'feblend': 'feBlend',
  'fecolormatrix': 'feColorMatrix',
  'fecomponenttransfer': 'feComponentTransfer',
  'fecomposite': 'feComposite', 'feconvolvematrix': 'feConvolveMatrix',
  'fediffuselighting': 'feDiffuseLighting',
  'fedisplacementmap': 'feDisplacementMap',
  'fedistantlight': 'feDistantLight', 'fedropshadow': 'feDropShadow',
  'feflood': 'feFlood', 'fefunca': 'feFuncA', 'fefuncb': 'feFuncB',
  'fefuncg': 'feFuncG', 'fefuncr': 'feFuncR',
  'fegaussianblur': 'feGaussianBlur', 'feimage': 'feImage',
  'femerge': 'feMerge', 'femergenode': 'feMergeNode',
  'femorphology': 'feMorphology', 'feoffset': 'feOffset',
  'fepointlight': 'fePointLight',
  'fespecularlighting': 'feSpecularLighting',
  'fespotlight': 'feSpotLight', 'fetile': 'feTile',
  'feturbulence': 'feTurbulence', 'foreignobject': 'foreignObject',
  'glyphref': 'glyphRef', 'lineargradient': 'linearGradient',
  'radialgradient': 'radialGradient', 'textpath': 'textPath',
};

/// The elements whose content is not markup that a head may hold.
const _headRaw = {'title', 'noframes', 'style', 'script', 'noscript'};

/// The elements a head may hold that are whole in one tag.
const _headed = {
  'base', 'basefont', 'bgsound', 'link', 'meta', //
};

const _voids = {
  'area', 'br', 'embed', 'img', 'keygen', 'wbr', 'input', 'param', //
  'source', 'track', 'hr', 'image',
};

/// Start tags body ignores.
const _ignored = {
  'caption', 'col', 'colgroup', 'frame', 'head', 'tbody', 'td', 'tfoot', //
  'th', 'thead', 'tr',
};

/// The formatting elements but `a` and `nobr`, which have rules of their
/// own.
const _formats = {
  'b', 'big', 'code', 'em', 'font', 'i', 's', 'small', 'strike', 'strong', //
  'tt', 'u',
};

const _blocks = {
  'address', 'article', 'aside', 'blockquote', 'center', 'details', //
  'dialog', 'dir', 'div', 'dl', 'fieldset', 'figcaption', 'figure', 'footer',
  'header', 'hgroup', 'main', 'menu', 'nav', 'ol', 'p', 'search', 'section',
  'summary', 'ul', 'pre', 'listing',
};

const _headings = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

/// The elements the standard closes when it generates implied end tags.
const _implying = {
  'dd', 'dt', 'li', 'optgroup', 'option', 'p', 'rb', 'rp', 'rt', 'rtc', //
};

/// The elements the standard does not object to finding open at the end.
const _closable = {
  ..._implying, 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'body', 'html', //
};

/// What bounds an element's scope.
const _scope = {
  'applet', 'caption', 'html', 'table', 'td', 'th', 'marquee', 'object', //
  'select', 'template',
};

const _button = {'button'};

const _listing = {'ol', 'ul'};

/// The standard's special category.
const _special = {
  'address', 'applet', 'area', 'article', 'aside', 'base', 'basefont', //
  'bgsound', 'blockquote', 'body', 'br', 'button', 'caption', 'center', 'col',
  'colgroup', 'dd', 'details', 'dir', 'div', 'dl', 'dt', 'embed', 'fieldset',
  'figcaption', 'figure', 'footer', 'form', 'frame', 'frameset', 'h1', 'h2',
  'h3', 'h4', 'h5', 'h6', 'head', 'header', 'hgroup', 'hr', 'html', 'iframe',
  'img', 'input', 'keygen', 'li', 'link', 'listing', 'main', 'marquee', 'menu',
  'meta', 'nav', 'noembed', 'noframes', 'noscript', 'object', 'ol', 'p',
  'param', 'plaintext', 'pre', 'script', 'search', 'section', 'select',
  'source', 'style', 'summary', 'table', 'tbody', 'td', 'template',
  'textarea', 'tfoot', 'th', 'thead', 'title', 'tr', 'track', 'ul', 'wbr',
  'xmp',
};

/// Whether the doctype [text] puts a document in quirks mode, as the
/// standard decides it from the doctype's name and identifiers.
bool _quirky(String text) {
  final (:name, :public, :system, :correct) = doctype(text);
  if (!correct || name != 'html') {
    return true;
  }
  final low = public?.toLowerCase();
  if (low != null &&
      (const {
            '-//w3o//dtd w3 html strict 3.0//en//',
            '-/w3c/dtd html 4.0 transitional/en',
            'html',
          }.contains(low) ||
          _quirkish.any(low.startsWith) ||
          (system == null &&
              (low.startsWith('-//w3c//dtd html 4.01 frameset//') ||
                  low.startsWith('-//w3c//dtd html 4.01 transitional//'))))) {
    return true;
  }
  return system?.toLowerCase() ==
      'http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd';
}

/// The public identifier prefixes that put a document in quirks mode.
const _quirkish = [
  '+//silmaril//dtd html pro v0r11 19970101//',
  '-//as//dtd html 3.0 aswedit + extensions//',
  '-//advasoft ltd//dtd html 3.0 aswedit + extensions//',
  '-//ietf//dtd html 2.0 level 1//',
  '-//ietf//dtd html 2.0 level 2//',
  '-//ietf//dtd html 2.0 strict level 1//',
  '-//ietf//dtd html 2.0 strict level 2//',
  '-//ietf//dtd html 2.0 strict//',
  '-//ietf//dtd html 2.0//',
  '-//ietf//dtd html 2.1e//',
  '-//ietf//dtd html 3.0//',
  '-//ietf//dtd html 3.2 final//',
  '-//ietf//dtd html 3.2//',
  '-//ietf//dtd html 3//',
  '-//ietf//dtd html level 0//',
  '-//ietf//dtd html level 1//',
  '-//ietf//dtd html level 2//',
  '-//ietf//dtd html level 3//',
  '-//ietf//dtd html strict level 0//',
  '-//ietf//dtd html strict level 1//',
  '-//ietf//dtd html strict level 2//',
  '-//ietf//dtd html strict level 3//',
  '-//ietf//dtd html strict//',
  '-//ietf//dtd html//',
  '-//metrius//dtd metrius presentational//',
  '-//microsoft//dtd internet explorer 2.0 html strict//',
  '-//microsoft//dtd internet explorer 2.0 html//',
  '-//microsoft//dtd internet explorer 2.0 tables//',
  '-//microsoft//dtd internet explorer 3.0 html strict//',
  '-//microsoft//dtd internet explorer 3.0 html//',
  '-//microsoft//dtd internet explorer 3.0 tables//',
  '-//netscape comm. corp.//dtd html//',
  '-//netscape comm. corp.//dtd strict html//',
  "-//o'reilly and associates//dtd html 2.0//",
  "-//o'reilly and associates//dtd html extended 1.0//",
  "-//o'reilly and associates//dtd html extended relaxed 1.0//",
  '-//sq//dtd html 2.0 hotmetal + extensions//',
  '-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//',
  '-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//',
  '-//spyglass//dtd html 2.0 extended//',
  '-//sun microsystems corp.//dtd hotjava html//',
  '-//sun microsystems corp.//dtd hotjava strict html//',
  '-//w3c//dtd html 3 1995-03-24//',
  '-//w3c//dtd html 3.2 draft//',
  '-//w3c//dtd html 3.2 final//',
  '-//w3c//dtd html 3.2//',
  '-//w3c//dtd html 3.2s draft//',
  '-//w3c//dtd html 4.0 frameset//',
  '-//w3c//dtd html 4.0 transitional//',
  '-//w3c//dtd html experimental 19960712//',
  '-//w3c//dtd html experimental 970421//',
  '-//w3c//dtd w3 html//',
  '-//w3o//dtd w3 html 3.0//',
  '-//webtechs//dtd mozilla html 2.0//',
  '-//webtechs//dtd mozilla html//',
];

/// Where a table's content may stand without being fostered.
const _tabular = {'table', 'tbody', 'template', 'tfoot', 'thead', 'tr'};

/// The start tags a caption or cell closes before.
const _tableParts = {
  'caption', 'col', 'colgroup', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', //
};

const _sections = {'tbody', 'tfoot', 'thead'};

/// What bounds table scope.
const _tableScope = {'html', 'table', 'template'};

const _tableContext = {'table', 'template', 'html'};
const _bodyContext = {'tbody', 'tfoot', 'thead', 'template', 'html'};
const _rowContext = {'tr', 'template', 'html'};

/// The elements generating every implied end tag closes.
const _thoroughly = {
  'caption', 'colgroup', 'dd', 'dt', 'li', 'optgroup', 'option', 'p', 'rb', //
  'rp', 'rt', 'rtc', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr',
};
