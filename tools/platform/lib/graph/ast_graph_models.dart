/// Typed AST input DTOs for graph mapping (internal to Graph Engine).
class AstProjectData {
  const AstProjectData({
    required this.projectName,
    this.projectRoot,
    this.generatedAt,
    required this.files,
    required this.classes,
    required this.methods,
    required this.imports,
    required this.importGraph,
    required this.enums,
    required this.extensions,
    required this.mixins,
    required this.inheritance,
    required this.firestoreWrites,
    required this.firestoreReads,
    required this.firestoreTransactions,
    required this.hiveBoxes,
  });

  final String projectName;
  final String? projectRoot;
  final String? generatedAt;
  final List<AstFileData> files;
  final List<AstTypeData> classes;
  final List<AstMethodData> methods;
  final Map<String, List<String>> imports;
  final Map<String, List<String>> importGraph;
  final List<AstTypeData> enums;
  final List<AstTypeData> extensions;
  final List<AstTypeData> mixins;
  final Map<String, AstInheritanceData> inheritance;
  final List<AstStorageAccessData> firestoreWrites;
  final List<AstStorageAccessData> firestoreReads;
  final List<AstStorageAccessData> firestoreTransactions;
  final List<AstStorageAccessData> hiveBoxes;
}

class AstFileData {
  const AstFileData({required this.path});

  final String path;
}

class AstTypeData {
  const AstTypeData({
    required this.key,
    required this.name,
    required this.file,
    this.superclass,
    this.interfaces = const [],
    this.mixins = const [],
    this.kind,
    this.abstract = false,
  });

  final String key;
  final String name;
  final String file;
  final String? superclass;
  final List<String> interfaces;
  final List<String> mixins;
  final String? kind;
  final bool abstract;
}

class AstMethodData {
  const AstMethodData({
    required this.key,
    required this.name,
    required this.file,
    this.className,
    this.callees = const [],
    this.callers = const [],
    this.isStatic = false,
    this.isConstructor = false,
  });

  final String key;
  final String name;
  final String file;
  final String? className;
  final List<String> callees;
  final List<String> callers;
  final bool isStatic;
  final bool isConstructor;
}

class AstInheritanceData {
  const AstInheritanceData({
    required this.name,
    this.extendsType,
    this.implementsTypes = const [],
    this.mixinTypes = const [],
  });

  final String name;
  final String? extendsType;
  final List<String> implementsTypes;
  final List<String> mixinTypes;
}

class AstStorageAccessData {
  const AstStorageAccessData({
    required this.file,
    required this.method,
    required this.target,
    this.kind,
    this.line,
  });

  final String file;
  final String method;
  final String target;
  final String? kind;
  final int? line;
}

class AstInvocationData {
  const AstInvocationData({
    required this.callerKey,
    required this.calleeKey,
  });

  final String callerKey;
  final String calleeKey;
}
