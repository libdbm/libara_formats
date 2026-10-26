/// What the tests read Dart's syntax against: the analyzer's parse of a
/// text, and the layer-3 elements the `dart` format reads, each written as
/// its kind, its extent in UTF-16 units of the text, and the name it
/// declares, in pre-order, so that the two compare as lists.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:libara/libara.dart';

import 'harness.dart';

/// The kinds of pair, which the analyzer has no nodes for.
const pairs = {'parens', 'brackets', 'braces', 'string', 'interpolation'};

/// One element as the tests compare it.
String entry(String kind, int start, int end, [String? name]) =>
    '$kind $start..$end${name == null ? '' : ' $name'}';

/// [entries], each with the start and end it was given, in pre-order: by
/// start, of two that start together the longer first, and of two alike,
/// a name after what it names, and otherwise as they are written.
List<String> ordered(List<(int, int, String)> entries) {
  int named((int, int, String) entry) => entry.$3.startsWith('name ') ? 1 : 0;
  return [
    for (final (_, _, written)
        in entries.toList()..sort(
          (one, other) => one.$1 != other.$1
              ? one.$1 - other.$1
              : one.$2 != other.$2
              ? other.$2 - one.$2
              : named(one) != named(other)
              ? named(one) - named(other)
              : one.$3.compareTo(other.$3),
        ))
      written,
  ];
}

/// The elements of layer 3 of [document], other than pairs, as [entry]
/// writes them.
List<String> ourSyntax(Layered<int> document) {
  final text = string(document.items);
  // Where each code point starts, in UTF-16 units, and where the last ends.
  final units = <int>[0];
  for (final rune in text.runes) {
    units.add(units.last + (rune > 0xFFFF ? 2 : 1));
  }
  final tokens = document.layer(2).items.cast<ARange>().toList();
  return ordered([
    for (final element in document.layer(3).items.cast<ARange>())
      if (!pairs.contains(said(element, '')) && element.length > 0)
        if ((
              units[tokens[element.start].start],
              units[tokens[element.end - 1].end],
            )
            case (final start, final end))
          (
            start,
            end,
            entry(
              said(element, '')!,
              start,
              end,
              said(element, 'name') ?? said(element, 'form'),
            ),
          ),
  ]);
}

/// What the analyzer parses [text] into, as [entry] writes our elements:
/// every declaration, statement, expression and type of more than one
/// token, each name a declaration declares, each annotation, parameter,
/// type parameter and initializer, each under the kind its row of
/// [_Syntax] maps it to. A pattern of more than one token is a `pattern`
/// saying its form where an element says its name.
///
/// A `>>` closing two type argument lists is one token here, so an element
/// the analyzer ends within one ends with it.
List<String> theirSyntax(String text) {
  final unit = parseString(content: text, throwIfDiagnostics: false).unit;
  final syntax = _Syntax(text);
  unit.accept(syntax);
  return ordered(syntax.found);
}

/// Maps the analyzer's nodes to our elements, one row for each kind of
/// node, collecting them in [found].
final class _Syntax extends RecursiveAstVisitor<void> {
  _Syntax(this.text);

  final String text;
  final found = <(int, int, String)>[];

  /// Where an element ending at [end] ends, past the rest of a `>>`.
  int _ended(int end) {
    var at = end;
    while (at > 0 &&
        at < text.length &&
        text[at - 1] == '>' &&
        text[at] == '>') {
      at++;
    }
    return at;
  }

  void add(AstNode node, String kind) {
    final start = switch (node) {
      AnnotatedNode(:final metadata) when metadata.isNotEmpty =>
        metadata.first.offset,
      AnnotatedNode(:final firstTokenAfterCommentAndMetadata) =>
        firstTokenAfterCommentAndMetadata.offset,
      _ => node.offset,
    };
    span(start, node.end, kind);
  }

  void span(int start, int end, String kind) {
    final over = _ended(end);
    found.add((start, over, entry(kind, start, over)));
  }

  /// [node] as [kind] where it spans more than one token.
  void several(AstNode node, String kind) {
    if (node.beginToken != node.endToken) {
      add(node, kind);
    }
  }

  void name(int start, int end, String said) =>
      found.add((start, end, entry('name', start, end, said)));

  void token(Token? token) {
    if (token != null) {
      name(token.offset, token.end, token.lexeme);
    }
  }

  @override
  void visitComment(Comment node) {}

  @override
  void visitCompilationUnit(CompilationUnit node) {
    for (final directive in node.directives) {
      add(directive, 'directive');
      directive.metadata.accept(this);
    }
    node.declarations.accept(this);
  }

  @override
  void visitAnnotation(Annotation node) {
    add(node, 'annotation');
    node.typeArguments?.accept(this);
    node.arguments?.accept(this);
  }

  // Declarations.

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    add(node, 'class');
    token(node.namePart.typeName);
    super.visitClassDeclaration(node);
  }

  @override
  void visitClassTypeAlias(ClassTypeAlias node) {
    add(node, 'class');
    token(node.name);
    super.visitClassTypeAlias(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    add(node, 'mixin');
    token(node.name);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    add(node, 'enum');
    token(node.namePart.typeName);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    add(node, 'value');
    token(node.name);
    super.visitEnumConstantDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    add(node, 'extension');
    token(node.name);
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    add(node, 'extension');
    token(node.namePart.typeName);
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    add(
      node,
      node.isGetter
          ? 'getter'
          : node.isSetter
          ? 'setter'
          : 'function',
    );
    token(node.name);
    node.metadata.accept(this);
    node.returnType?.accept(this);
    // The function expression is the declaration's own, not a closure.
    final function = node.functionExpression;
    function.typeParameters?.accept(this);
    function.parameters?.accept(this);
    function.body.accept(this);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    add(node, 'variable');
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    add(node, 'typedef');
    token(node.name);
    super.visitGenericTypeAlias(node);
  }

  @override
  void visitFunctionTypeAlias(FunctionTypeAlias node) {
    add(node, 'typedef');
    token(node.name);
    super.visitFunctionTypeAlias(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    add(node, 'constructor');
    final (first, named) = (node.typeName, node.name);
    if (first != null) {
      name(
        first.offset,
        named?.end ?? first.end,
        '${first.name}${named == null ? '' : '.${named.lexeme}'}',
      );
    } else {
      // Declared by `new` or `factory`, it says only its own name.
      token(named);
    }
    node.metadata.accept(this);
    node.parameters.accept(this);
    node.initializers.accept(this);
    node.redirectedConstructor?.accept(this);
    node.body.accept(this);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    add(
      node,
      node.isGetter
          ? 'getter'
          : node.isSetter
          ? 'setter'
          : 'method',
    );
    if (node.operatorKeyword case final operator?) {
      name(operator.offset, node.name.end, 'operator ${node.name.lexeme}');
    } else {
      token(node.name);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    add(node, 'field');
    super.visitFieldDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    token(node.name);
    node.initializer?.accept(this);
  }

  @override
  void visitTypeParameter(TypeParameter node) {
    add(node, 'generic');
    token(node.name);
    super.visitTypeParameter(node);
  }

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    add(node, 'parameter');
    token(node.name);
    super.visitRegularFormalParameter(node);
  }

  @override
  void visitFieldFormalParameter(FieldFormalParameter node) {
    add(node, 'parameter');
    token(node.name);
    super.visitFieldFormalParameter(node);
  }

  @override
  void visitSuperFormalParameter(SuperFormalParameter node) {
    add(node, 'parameter');
    token(node.name);
    super.visitSuperFormalParameter(node);
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    add(node, 'initializer');
    node.expression.accept(this);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    add(node, 'initializer');
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    add(node, 'initializer');
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  void visitAssertInitializer(AssertInitializer node) {
    add(node, 'initializer');
    super.visitAssertInitializer(node);
  }

  // Types.

  @override
  void visitNamedType(NamedType node) {
    several(node, 'type');
    super.visitNamedType(node);
  }

  @override
  void visitGenericFunctionType(GenericFunctionType node) {
    add(node, 'type');
    super.visitGenericFunctionType(node);
  }

  @override
  void visitRecordTypeAnnotation(RecordTypeAnnotation node) {
    add(node, 'type');
    super.visitRecordTypeAnnotation(node);
  }

  // Statements.

  @override
  void visitBlock(Block node) {
    add(node, 'block');
    super.visitBlock(node);
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    add(node, 'statement');
    super.visitExpressionStatement(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    add(node, 'if');
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    add(node, 'for');
    super.visitForStatement(node);
  }

  @override
  void visitForPartsWithDeclarations(ForPartsWithDeclarations node) {
    add(node.variables, 'variable');
    super.visitForPartsWithDeclarations(node);
  }

  @override
  void visitForPartsWithPattern(ForPartsWithPattern node) {
    add(node.variables, 'variable');
    super.visitForPartsWithPattern(node);
  }

  @override
  void visitForEachPartsWithDeclaration(ForEachPartsWithDeclaration node) {
    add(node.loopVariable, 'variable');
    token(node.loopVariable.name);
    super.visitForEachPartsWithDeclaration(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    add(node, 'while');
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    add(node, 'do');
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    add(node, 'switch');
    super.visitSwitchStatement(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    add(node, 'case');
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    add(node, 'case');
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchDefault(SwitchDefault node) {
    add(node, 'case');
    super.visitSwitchDefault(node);
  }

  @override
  void visitTryStatement(TryStatement node) {
    add(node, 'try');
    node.body.accept(this);
    node.catchClauses.accept(this);
    if ((node.finallyKeyword, node.finallyBlock) case (
      final keyword?,
      final block?,
    )) {
      span(keyword.offset, block.end, 'finally');
      block.accept(this);
    }
  }

  @override
  void visitCatchClause(CatchClause node) {
    add(node, 'catch');
    token(node.exceptionParameter?.name);
    token(node.stackTraceParameter?.name);
    super.visitCatchClause(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    add(node, 'return');
    super.visitReturnStatement(node);
  }

  @override
  void visitBreakStatement(BreakStatement node) => add(node, 'break');

  @override
  void visitContinueStatement(ContinueStatement node) => add(node, 'continue');

  @override
  void visitYieldStatement(YieldStatement node) {
    add(node, 'yield');
    super.visitYieldStatement(node);
  }

  @override
  void visitAssertStatement(AssertStatement node) {
    add(node, 'assert');
    super.visitAssertStatement(node);
  }

  @override
  void visitLabel(Label node) => add(node, 'label');

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    add(node, 'variable');
    super.visitVariableDeclarationStatement(node);
  }

  @override
  void visitPatternVariableDeclarationStatement(
    PatternVariableDeclarationStatement node,
  ) {
    add(node, 'variable');
    super.visitPatternVariableDeclarationStatement(node);
  }

  // Expressions.

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    add(node, 'assignment');
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPatternAssignment(PatternAssignment node) {
    add(node, 'assignment');
    super.visitPatternAssignment(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    add(node, 'conditional');
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    add(node, 'binary');
    super.visitBinaryExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    add(node, 'prefix');
    super.visitPrefixExpression(node);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    add(node, 'prefix');
    super.visitAwaitExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    add(node, 'postfix');
    super.visitPostfixExpression(node);
  }

  @override
  void visitIsExpression(IsExpression node) {
    add(node, 'is');
    super.visitIsExpression(node);
  }

  @override
  void visitAsExpression(AsExpression node) {
    add(node, 'as');
    super.visitAsExpression(node);
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    add(node, 'throw');
    super.visitThrowExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    add(node, 'call');
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    add(node, 'call');
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    add(node, 'call');
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    add(node, 'call');
    super.visitDotShorthandInvocation(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    add(node, 'call');
    super.visitDotShorthandConstructorInvocation(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    add(node, 'argument');
    node.argumentExpression.accept(this);
  }

  @override
  void visitRecordLiteralNamedField(RecordLiteralNamedField node) {
    add(node, 'argument');
    node.fieldExpression.accept(this);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    add(node, 'index');
    super.visitIndexExpression(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    add(node, 'property');
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    add(node, 'property');
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitDotShorthandPropertyAccess(DotShorthandPropertyAccess node) {
    add(node, 'property');
    super.visitDotShorthandPropertyAccess(node);
  }

  @override
  void visitCascadeExpression(CascadeExpression node) {
    add(node, 'cascade');
    for (final section in node.cascadeSections) {
      add(section, 'section');
    }
    super.visitCascadeExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    add(node, 'closure');
    super.visitFunctionExpression(node);
  }

  @override
  void visitFunctionReference(FunctionReference node) {
    add(node, 'instantiation');
    super.visitFunctionReference(node);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    add(node, 'list');
    super.visitListLiteral(node);
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    add(node, _mapped(node) ? 'map' : 'set');
    super.visitSetOrMapLiteral(node);
  }

  /// Whether [node] reads as a map, by its syntax alone: with two type
  /// arguments, or, with none, holding an entry, or holding no value.
  static bool _mapped(SetOrMapLiteral node) {
    if (node.typeArguments?.arguments.length case final count?) {
      return count == 2;
    }
    var (entries, values) = (false, false);
    void look(CollectionElement element) {
      switch (element) {
        case MapLiteralEntry():
          entries = true;
        case IfElement(:final thenElement, :final elseElement):
          look(thenElement);
          if (elseElement != null) {
            look(elseElement);
          }
        case ForElement(:final body):
          look(body);
        case SpreadElement():
          break;
        default:
          values = true;
      }
    }

    node.elements.forEach(look);
    return entries || !values;
  }

  @override
  void visitRecordLiteral(RecordLiteral node) {
    add(node, 'record');
    super.visitRecordLiteral(node);
  }

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    add(node, 'entry');
    super.visitMapLiteralEntry(node);
  }

  @override
  void visitSpreadElement(SpreadElement node) {
    add(node, 'spread');
    super.visitSpreadElement(node);
  }

  @override
  void visitNullAwareElement(NullAwareElement node) {
    add(node, 'aware');
    super.visitNullAwareElement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    add(node, 'if');
    super.visitIfElement(node);
  }

  @override
  void visitForElement(ForElement node) {
    add(node, 'for');
    super.visitForElement(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    add(node, 'switch');
    super.visitSwitchExpression(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    add(node, 'case');
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    add(node, 'strings');
    super.visitAdjacentStrings(node);
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) => add(node, 'symbol');

  // Patterns.

  /// [node] as a `pattern` of [form] where it spans more than one token.
  void pattern(AstNode node, String form) {
    if (node.beginToken != node.endToken) {
      final over = _ended(node.end);
      found.add((node.offset, over, entry('pattern', node.offset, over, form)));
    }
  }

  @override
  void visitConstantPattern(ConstantPattern node) {
    pattern(node, 'constant');
    super.visitConstantPattern(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    pattern(node, 'variable');
    token(node.name);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitWildcardPattern(WildcardPattern node) {
    pattern(node, 'wildcard');
    super.visitWildcardPattern(node);
  }

  @override
  void visitListPattern(ListPattern node) {
    pattern(node, 'list');
    super.visitListPattern(node);
  }

  @override
  void visitMapPattern(MapPattern node) {
    pattern(node, 'map');
    super.visitMapPattern(node);
  }

  @override
  void visitMapPatternEntry(MapPatternEntry node) {
    add(node, 'entry');
    super.visitMapPatternEntry(node);
  }

  @override
  void visitRecordPattern(RecordPattern node) {
    pattern(node, 'record');
    super.visitRecordPattern(node);
  }

  @override
  void visitObjectPattern(ObjectPattern node) {
    pattern(node, 'object');
    super.visitObjectPattern(node);
  }

  @override
  void visitPatternField(PatternField node) {
    if (node.name != null) {
      add(node, 'argument');
    }
    super.visitPatternField(node);
  }

  @override
  void visitRelationalPattern(RelationalPattern node) {
    pattern(node, 'relational');
    super.visitRelationalPattern(node);
  }

  @override
  void visitLogicalOrPattern(LogicalOrPattern node) {
    pattern(node, 'logical');
    super.visitLogicalOrPattern(node);
  }

  @override
  void visitLogicalAndPattern(LogicalAndPattern node) {
    pattern(node, 'logical');
    super.visitLogicalAndPattern(node);
  }

  @override
  void visitCastPattern(CastPattern node) {
    pattern(node, 'cast');
    super.visitCastPattern(node);
  }

  @override
  void visitNullCheckPattern(NullCheckPattern node) {
    pattern(node, 'check');
    super.visitNullCheckPattern(node);
  }

  @override
  void visitNullAssertPattern(NullAssertPattern node) {
    pattern(node, 'assert');
    super.visitNullAssertPattern(node);
  }

  @override
  void visitRestPatternElement(RestPatternElement node) {
    pattern(node, 'rest');
    super.visitRestPatternElement(node);
  }
}
