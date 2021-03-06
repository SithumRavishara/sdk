// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';
import 'package:analyzer/src/summary/format.dart';
import 'package:analyzer/src/summary/idl.dart';
import 'package:analyzer/src/summary2/ast_binary_reader.dart';
import 'package:analyzer/src/summary2/linked_bundle_context.dart';
import 'package:analyzer/src/summary2/reference.dart';
import 'package:analyzer/src/summary2/tokens_context.dart';

/// The context of a unit - the context of the bundle, and the unit tokens.
class LinkedUnitContext {
  final LinkedBundleContext bundleContext;
  final String uriStr;
  final LinkedNodeUnit data;
  final TokensContext tokensContext;

  AstBinaryReader _astReader;
  CompilationUnit _unit;
  bool _hasDirectivesRead = false;

  LinkedUnitContext(this.bundleContext, this.uriStr, this.data,
      {CompilationUnit unit})
      : tokensContext = data != null ? TokensContext(data.tokens) : null {
    _astReader = AstBinaryReader(this);
    _unit = unit;
    _hasDirectivesRead = _unit != null;
  }

  CompilationUnit get unit => _unit;

  CompilationUnit get unit_withDeclarations {
    if (_unit == null) {
      _astReader.lazyNamesOnly = true;
      _unit = _astReader.readNode(data.node);
      _astReader.lazyNamesOnly = false;
    }
    return _unit;
  }

  CompilationUnit get unit_withDirectives {
    if (!_hasDirectivesRead) {
      var directiveDataList = data.node.compilationUnit_directives;
      for (var i = 0; i < directiveDataList.length; ++i) {
        var directiveData = directiveDataList[i];
        _unit.directives[i] = _astReader.readNode(directiveData);
      }
      _hasDirectivesRead = true;
    }
    return _unit;
  }

  Iterable<LinkedNode> classFields(LinkedNode class_) sync* {
    for (var declaration in class_.classOrMixinDeclaration_members) {
      if (declaration.kind == LinkedNodeKind.fieldDeclaration) {
        var variableList = declaration.fieldDeclaration_fields;
        for (var field in variableList.variableDeclarationList_variables) {
          yield field;
        }
      }
    }
  }

  Uri directiveUri(Uri libraryUri, UriBasedDirective directive) {
    var relativeUriStr = directive.uri.stringValue;
    var relativeUri = Uri.parse(relativeUriStr);
    return resolveRelativeUri(libraryUri, relativeUri);
  }

  String getCommentText(LinkedNode comment) {
    if (comment == null) return null;

    return comment.comment_tokens.map(getTokenLexeme).join('\n');
  }

  String getConstructorDeclarationName(LinkedNode node) {
    var name = node.constructorDeclaration_name;
    if (name != null) {
      return getSimpleName(name);
    }
    return '';
  }

  String getFormalParameterName(LinkedNode node) {
    return getSimpleName(node.normalFormalParameter_identifier);
  }

  List<LinkedNode> getFormalParameters(LinkedNode node) {
    LinkedNode parameterList;
    var kind = node.kind;
    if (kind == LinkedNodeKind.constructorDeclaration) {
      parameterList = node.constructorDeclaration_parameters;
    } else if (kind == LinkedNodeKind.functionDeclaration) {
      return getFormalParameters(node.functionDeclaration_functionExpression);
    } else if (kind == LinkedNodeKind.functionExpression) {
      parameterList = node.functionExpression_formalParameters;
    } else if (kind == LinkedNodeKind.functionTypeAlias) {
      parameterList = node.functionTypeAlias_formalParameters;
    } else if (kind == LinkedNodeKind.genericFunctionType) {
      parameterList = node.genericFunctionType_formalParameters;
    } else if (kind == LinkedNodeKind.methodDeclaration) {
      parameterList = node.methodDeclaration_formalParameters;
    } else {
      throw UnimplementedError('$kind');
    }
    return parameterList?.formalParameterList_parameters;
  }

  DartType getFormalParameterType(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.defaultFormalParameter) {
      return getFormalParameterType(node.defaultFormalParameter_parameter);
    }
    if (kind == LinkedNodeKind.fieldFormalParameter) {
      return getType(node.fieldFormalParameter_type2);
    }
    if (kind == LinkedNodeKind.functionTypedFormalParameter) {
      return getType(node.functionTypedFormalParameter_type2);
    }
    if (kind == LinkedNodeKind.simpleFormalParameter) {
      return getType(node.simpleFormalParameter_type2);
    }
    throw UnimplementedError('$kind');
  }

  ImplementsClause getImplementsClause(AstNode node) {
    if (node is ClassDeclaration) {
      _ensure_classDeclaration_implementsClause(node);
      return node.implementsClause;
    } else if (node is ClassTypeAlias) {
      _ensure_classTypeAlias_implementsClause(node);
      return node.implementsClause;
    } else {
      throw UnimplementedError('${node.runtimeType}');
    }
  }

  InterfaceType getInterfaceType(LinkedNodeType linkedType) {
    return bundleContext.getInterfaceType(linkedType);
  }

  List<LinkedNode> getLibraryMetadataOrEmpty(LinkedNode unit) {
    for (var directive in unit.compilationUnit_directives) {
      if (directive.kind == LinkedNodeKind.libraryDirective) {
        return getMetadataOrEmpty(directive);
      }
    }
    return const <LinkedNode>[];
  }

  List<LinkedNode> getMetadataOrEmpty(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.classDeclaration ||
        kind == LinkedNodeKind.classTypeAlias ||
        kind == LinkedNodeKind.constructorDeclaration ||
        kind == LinkedNodeKind.enumConstantDeclaration ||
        kind == LinkedNodeKind.enumDeclaration ||
        kind == LinkedNodeKind.exportDirective ||
        kind == LinkedNodeKind.functionDeclaration ||
        kind == LinkedNodeKind.functionTypeAlias ||
        kind == LinkedNodeKind.libraryDirective ||
        kind == LinkedNodeKind.importDirective ||
        kind == LinkedNodeKind.methodDeclaration ||
        kind == LinkedNodeKind.mixinDeclaration ||
        kind == LinkedNodeKind.partDirective ||
        kind == LinkedNodeKind.partOfDirective ||
        kind == LinkedNodeKind.variableDeclaration) {
      return node.annotatedNode_metadata;
    }
    if (kind == LinkedNodeKind.defaultFormalParameter) {
      return getMetadataOrEmpty(node.defaultFormalParameter_parameter);
    }
    if (kind == LinkedNodeKind.fieldFormalParameter ||
        kind == LinkedNodeKind.functionTypedFormalParameter ||
        kind == LinkedNodeKind.simpleFormalParameter) {
      return node.normalFormalParameter_metadata;
    }
    return const <LinkedNode>[];
  }

  String getMethodName(LinkedNode node) {
    return getSimpleName(node.methodDeclaration_name);
  }

  DartType getReturnType(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.functionDeclaration) {
      return getType(node.functionDeclaration_returnType2);
    } else if (kind == LinkedNodeKind.functionTypeAlias) {
      return getType(node.functionTypeAlias_returnType2);
    } else if (kind == LinkedNodeKind.genericFunctionType) {
      return getType(node.genericFunctionType_returnType2);
    } else if (kind == LinkedNodeKind.methodDeclaration) {
      return getType(node.methodDeclaration_returnType2);
    } else {
      throw UnimplementedError('$kind');
    }
  }

  String getSimpleName(LinkedNode node) {
    return getTokenLexeme(node.simpleIdentifier_token);
  }

  List<String> getSimpleNameList(List<LinkedNode> nodeList) {
    return nodeList.map(getSimpleName).toList();
  }

  int getSimpleOffset(LinkedNode node) {
    return getTokenOffset(node.simpleIdentifier_token);
  }

  String getStringContent(LinkedNode node) {
    return node.simpleStringLiteral_value;
  }

  TypeName getSuperclass(AstNode node) {
    if (node is ClassDeclaration) {
      _ensure_classDeclaration_extendsClause(node);
      return node.extendsClause?.superclass;
    } else if (node is ClassTypeAlias) {
      _ensure_classTypeAlias_superclass(node);
      return node.superclass;
    } else {
      throw StateError('${node.runtimeType}');
    }
  }

  String getTokenLexeme(int token) {
    return tokensContext.lexeme(token);
  }

  int getTokenOffset(int token) {
    return tokensContext.offset(token);
  }

  DartType getType(LinkedNodeType linkedType) {
    return bundleContext.getType(linkedType);
  }

  DartType getTypeAnnotationType(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.genericFunctionType) {
      return getType(node.genericFunctionType_type);
    } else if (kind == LinkedNodeKind.typeName) {
      return getType(node.typeName_type);
    } else {
      throw UnimplementedError('$kind');
    }
  }

  TypeParameterList getTypeParameters2(AstNode node) {
    if (node is ClassDeclaration) {
      _ensure_classDeclaration_typeParameters(node);
      return node.typeParameters;
    } else if (node is ClassTypeAlias) {
      _ensure_classTypeAlias_typeParameters(node);
      return node.typeParameters;
    } else {
      throw UnimplementedError('${node.runtimeType}');
    }
  }

  String getUnitMemberName(LinkedNode node) {
    return getSimpleName(node.namedCompilationUnitMember_name);
  }

  String getVariableName(LinkedNode node) {
    return getSimpleName(node.variableDeclaration_name);
  }

  WithClause getWithClause(AstNode node) {
    if (node is ClassDeclaration) {
      _ensure_classDeclaration_withClause(node);
      return node.withClause;
    } else if (node is ClassTypeAlias) {
      _ensure_classTypeAlias_withClause(node);
      return node.withClause;
    } else {
      throw UnimplementedError('${node.runtimeType}');
    }
  }

  bool isAbstract(LinkedNode node) {
    return node.kind == LinkedNodeKind.methodDeclaration &&
        node.methodDeclaration_body.kind == LinkedNodeKind.emptyFunctionBody;
  }

  bool isAsynchronous(LinkedNode node) {
    LinkedNode body = _getFunctionBody(node);
    if (body.kind == LinkedNodeKind.blockFunctionBody) {
      return isAsyncKeyword(body.blockFunctionBody_keyword);
    } else if (body.kind == LinkedNodeKind.emptyFunctionBody) {
      return false;
    } else {
      return isAsyncKeyword(body.expressionFunctionBody_keyword);
    }
  }

  bool isAsyncKeyword(int token) {
    return tokensContext.type(token) == UnlinkedTokenType.ASYNC;
  }

  bool isConst(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.defaultFormalParameter) {
      return isConst(node.defaultFormalParameter_parameter);
    }
    if (kind == LinkedNodeKind.simpleFormalParameter) {
      return isConstKeyword(node.simpleFormalParameter_keyword);
    }
    if (kind == LinkedNodeKind.variableDeclaration) {
      return node.variableDeclaration_declaration.isConst;
    }
    throw UnimplementedError('$kind');
  }

  bool isConstKeyword(int token) {
    return tokensContext.type(token) == UnlinkedTokenType.CONST;
  }

  bool isConstVariableList(LinkedNode node) {
    return isConstKeyword(node.variableDeclarationList_keyword);
  }

  bool isExternal(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.constructorDeclaration) {
      return node.constructorDeclaration_externalKeyword != 0;
    } else if (kind == LinkedNodeKind.functionDeclaration) {
      return node.functionDeclaration_externalKeyword != 0;
    } else if (kind == LinkedNodeKind.methodDeclaration) {
      return node.methodDeclaration_externalKeyword != 0;
    } else {
      throw UnimplementedError('$kind');
    }
  }

  bool isFinal(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.defaultFormalParameter) {
      return isFinal(node.defaultFormalParameter_parameter);
    }
    if (kind == LinkedNodeKind.enumConstantDeclaration) {
      return false;
    }
    if (kind == LinkedNodeKind.fieldFormalParameter) {
      return isFinalKeyword(node.fieldFormalParameter_keyword);
    }
    if (kind == LinkedNodeKind.functionTypedFormalParameter) {
      return false;
    }
    if (kind == LinkedNodeKind.simpleFormalParameter) {
      return isFinalKeyword(node.simpleFormalParameter_keyword);
    }
    if (kind == LinkedNodeKind.variableDeclaration) {
      return node.variableDeclaration_declaration.isFinal;
    }
    throw UnimplementedError('$kind');
  }

  bool isFinalKeyword(int token) {
    return tokensContext.type(token) == UnlinkedTokenType.FINAL;
  }

  bool isFinalVariableList(LinkedNode node) {
    return isFinalKeyword(node.variableDeclarationList_keyword);
  }

  bool isFunction(LinkedNode node) {
    return node.kind == LinkedNodeKind.functionDeclaration;
  }

  bool isGenerator(LinkedNode node) {
    LinkedNode body = _getFunctionBody(node);
    if (body.kind == LinkedNodeKind.blockFunctionBody) {
      return body.blockFunctionBody_star != 0;
    }
    return false;
  }

  bool isGetter(LinkedNode node) {
    return isGetterMethod(node) || isGetterFunction(node);
  }

  bool isGetterFunction(LinkedNode node) {
    return isFunction(node) &&
        _isGetToken(node.functionDeclaration_propertyKeyword);
  }

  bool isGetterMethod(LinkedNode node) {
    return isMethod(node) &&
        _isGetToken(node.methodDeclaration_propertyKeyword);
  }

  bool isLibraryKeyword(int token) {
    return tokensContext.type(token) == UnlinkedTokenType.LIBRARY;
  }

  bool isMethod(LinkedNode node) {
    return node.kind == LinkedNodeKind.methodDeclaration;
  }

  bool isSetter(LinkedNode node) {
    return isSetterMethod(node) || isSetterFunction(node);
  }

  bool isSetterFunction(LinkedNode node) {
    return isFunction(node) &&
        _isSetToken(node.functionDeclaration_propertyKeyword);
  }

  bool isSetterMethod(LinkedNode node) {
    return isMethod(node) &&
        _isSetToken(node.methodDeclaration_propertyKeyword);
  }

  bool isStatic(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.functionDeclaration) {
      return true;
    } else if (kind == LinkedNodeKind.methodDeclaration) {
      return node.methodDeclaration_modifierKeyword != 0;
    } else if (kind == LinkedNodeKind.variableDeclaration) {
      return node.variableDeclaration_declaration.isStatic;
    }
    throw UnimplementedError('$kind');
  }

  bool isSyncKeyword(int token) {
    return tokensContext.type(token) == UnlinkedTokenType.SYNC;
  }

  void loadClassMemberReferences(Reference reference) {
    var node = reference.node;
    if (node.kind != LinkedNodeKind.classDeclaration &&
        node.kind != LinkedNodeKind.mixinDeclaration) {
      return;
    }

    var constructorContainerRef = reference.getChild('@constructor');
    var fieldContainerRef = reference.getChild('@field');
    var methodContainerRef = reference.getChild('@method');
    var getterContainerRef = reference.getChild('@getter');
    var setterContainerRef = reference.getChild('@setter');
    for (var member in node.classOrMixinDeclaration_members) {
      if (member.kind == LinkedNodeKind.constructorDeclaration) {
        var name = getConstructorDeclarationName(member);
        constructorContainerRef.getChild(name).node = member;
      } else if (member.kind == LinkedNodeKind.fieldDeclaration) {
        var variableList = member.fieldDeclaration_fields;
        for (var field in variableList.variableDeclarationList_variables) {
          var name = getSimpleName(field.variableDeclaration_name);
          fieldContainerRef.getChild(name).node = field;
        }
      } else if (member.kind == LinkedNodeKind.methodDeclaration) {
        var name = getSimpleName(member.methodDeclaration_name);
        var propertyKeyword = member.methodDeclaration_propertyKeyword;
        if (_isGetToken(propertyKeyword)) {
          getterContainerRef.getChild(name).node = member;
        } else if (_isSetToken(propertyKeyword)) {
          setterContainerRef.getChild(name).node = member;
        } else {
          methodContainerRef.getChild(name).node = member;
        }
      }
    }
  }

  Expression readInitializer(ElementImpl enclosing, LinkedNode linkedNode) {
    return _astReader.withLocalScope(enclosing, () {
      if (linkedNode.kind == LinkedNodeKind.defaultFormalParameter) {
        var data = linkedNode.defaultFormalParameter_defaultValue;
        return _astReader.readNode(data);
      }
      var data = linkedNode.variableDeclaration_initializer;
      return _astReader.readNode(data);
    });
  }

  AstNode readNode(LinkedNode linkedNode) {
    return _astReader.readNode(linkedNode);
  }

  void setReturnType(LinkedNodeBuilder node, DartType type) {
    throw UnimplementedError();
//    var typeData = bundleContext.linking.writeType(type);
//    node.functionDeclaration_returnType2 = typeData;
  }

  void setVariableType(LinkedNodeBuilder node, DartType type) {
    throw UnimplementedError();
//    var typeData = bundleContext.linking.writeType(type);
//    node.simpleFormalParameter_type2 = typeData;
  }

  Iterable<LinkedNode> topLevelVariables(LinkedNode unit) sync* {
    for (var declaration in unit.compilationUnit_declarations) {
      if (declaration.kind == LinkedNodeKind.topLevelVariableDeclaration) {
        var variableList = declaration.topLevelVariableDeclaration_variableList;
        for (var variable in variableList.variableDeclarationList_variables) {
          yield variable;
        }
      }
    }
  }

  void _ensure_classDeclaration_extendsClause(ClassDeclaration node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classDeclaration_extendsClause) {
      node.extendsClause = _astReader.readNode(
        lazy.data.classDeclaration_extendsClause,
      );
      lazy.has_classDeclaration_extendsClause = true;
    }
  }

  void _ensure_classDeclaration_implementsClause(ClassDeclaration node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classDeclaration_implementsClause) {
      node.implementsClause = _astReader.readNode(
        lazy.data.classOrMixinDeclaration_implementsClause,
      );
      lazy.has_classDeclaration_implementsClause = true;
    }
  }

  void _ensure_classDeclaration_typeParameters(ClassDeclaration node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classDeclaration_typeParameters) {
      node.typeParameters = _astReader.readNode(
        lazy.data.classOrMixinDeclaration_typeParameters,
      );
      lazy.has_classDeclaration_typeParameters = true;
    }
  }

  void _ensure_classDeclaration_withClause(ClassDeclaration node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classDeclaration_withClause) {
      node.withClause = _astReader.readNode(
        lazy.data.classDeclaration_withClause,
      );
      lazy.has_classDeclaration_withClause = true;
    }
  }

  void _ensure_classTypeAlias_implementsClause(ClassTypeAlias node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classTypeAlias_implementsClause) {
      node.implementsClause = _astReader.readNode(
        lazy.data.classTypeAlias_implementsClause,
      );
      lazy.has_classTypeAlias_implementsClause = true;
    }
  }

  void _ensure_classTypeAlias_superclass(ClassTypeAlias node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classTypeAlias_superclass) {
      node.superclass = _astReader.readNode(
        lazy.data.classTypeAlias_superclass,
      );
      lazy.has_classTypeAlias_superclass = true;
    }
  }

  void _ensure_classTypeAlias_typeParameters(ClassTypeAlias node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classTypeAlias_typeParameters) {
      node.typeParameters = _astReader.readNode(
        lazy.data.classTypeAlias_typeParameters,
      );
      lazy.has_classTypeAlias_typeParameters = true;
    }
  }

  void _ensure_classTypeAlias_withClause(ClassTypeAlias node) {
    var lazy = LazyAst.get(node);
    if (lazy != null && !lazy.has_classTypeAlias_withClause) {
      node.withClause = _astReader.readNode(
        lazy.data.classTypeAlias_withClause,
      );
      lazy.has_classTypeAlias_withClause = true;
    }
  }

  LinkedNode _getFunctionBody(LinkedNode node) {
    var kind = node.kind;
    if (kind == LinkedNodeKind.constructorDeclaration) {
      return node.constructorDeclaration_body;
    } else if (kind == LinkedNodeKind.functionDeclaration) {
      return _getFunctionBody(node.functionDeclaration_functionExpression);
    } else if (kind == LinkedNodeKind.functionExpression) {
      return node.functionExpression_body;
    } else if (kind == LinkedNodeKind.methodDeclaration) {
      return node.methodDeclaration_body;
    } else {
      throw UnimplementedError('$kind');
    }
  }

  bool _isGetToken(int token) {
    return tokensContext.type(token) == UnlinkedTokenType.GET;
  }

  bool _isSetToken(int token) {
    return tokensContext.type(token) == UnlinkedTokenType.SET;
  }

  static List<LinkedNode> getTypeParameters(LinkedNode node) {
    LinkedNode typeParameterList;
    var kind = node.kind;
    if (kind == LinkedNodeKind.classTypeAlias) {
      typeParameterList = node.classTypeAlias_typeParameters;
    } else if (kind == LinkedNodeKind.classDeclaration ||
        kind == LinkedNodeKind.mixinDeclaration) {
      typeParameterList = node.classOrMixinDeclaration_typeParameters;
    } else if (kind == LinkedNodeKind.constructorDeclaration) {
      return const [];
    } else if (kind == LinkedNodeKind.functionDeclaration) {
      return getTypeParameters(node.functionDeclaration_functionExpression);
    } else if (kind == LinkedNodeKind.functionExpression) {
      typeParameterList = node.functionExpression_typeParameters;
    } else if (kind == LinkedNodeKind.functionTypeAlias) {
      typeParameterList = node.functionTypeAlias_typeParameters;
    } else if (kind == LinkedNodeKind.genericFunctionType) {
      typeParameterList = node.genericFunctionType_typeParameters;
    } else if (kind == LinkedNodeKind.genericTypeAlias) {
      typeParameterList = node.genericTypeAlias_typeParameters;
    } else if (kind == LinkedNodeKind.methodDeclaration) {
      typeParameterList = node.methodDeclaration_typeParameters;
    } else {
      throw UnimplementedError('$kind');
    }
    return typeParameterList?.typeParameterList_typeParameters;
  }
}
