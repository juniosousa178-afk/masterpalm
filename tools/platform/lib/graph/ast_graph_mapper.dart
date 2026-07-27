import 'ast_graph_models.dart';
import 'graph_exceptions.dart';

/// Parses AST report maps from [AstProvider] into typed DTOs.
class AstGraphMapper {
  const AstGraphMapper();

  AstProjectData parse(Map<String, dynamic> report) {
    if (report.isEmpty) {
      throw GraphParseException('AST report is empty');
    }

    final meta = report['meta'] as Map<String, dynamic>? ?? {};
    final projectRoot = meta['repo_root']?.toString();
    final projectName = _projectName(projectRoot);

    final imports = _parseImports(report['imports']);
    final files = imports.keys.map((path) => AstFileData(path: path)).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    return AstProjectData(
      projectName: projectName,
      projectRoot: projectRoot,
      generatedAt: meta['generated_at']?.toString(),
      files: files,
      classes: _parseTypes(report['classes'], isClass: true),
      methods: _parseMethods(report['methods']),
      imports: imports,
      importGraph: _parseImportGraph(report['import_graph']),
      enums: _parseTypes(report['enums'], isClass: false),
      extensions: _parseTypes(report['extensions'], isClass: false),
      mixins: _parseTypes(report['mixins'], isClass: false),
      inheritance: _parseInheritance(report['inheritance']),
      firestoreWrites: _parseStorage(report['firestore_writes']),
      firestoreReads: _parseStorage(report['firestore_reads']),
      firestoreTransactions: _parseStorage(report['firestore_transactions']),
      hiveBoxes: _parseHiveBoxes(report['hive_boxes']),
    );
  }

  String _projectName(String? root) {
    if (root == null || root.isEmpty) return 'masterpalm';
    final normalized = root.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? 'masterpalm' : parts.last;
  }

  Map<String, List<String>> _parseImports(Object? value) {
    if (value is! Map) return {};
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      final imports = (entry.value as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList()
        ..sort();
      result[entry.key.toString()] = imports;
    }
    final keys = result.keys.toList()..sort();
    return {for (final key in keys) key: result[key]!};
  }

  Map<String, List<String>> _parseImportGraph(Object? value) {
    return _parseImports(value);
  }

  List<AstTypeData> _parseTypes(Object? value, {required bool isClass}) {
    if (value is! Map) return [];
    final items = <AstTypeData>[];
    for (final entry in value.entries) {
      final map = entry.value as Map<dynamic, dynamic>;
      items.add(
        AstTypeData(
          key: entry.key.toString(),
          name: map['name']?.toString() ?? entry.key.toString(),
          file: map['file']?.toString() ?? '',
          superclass:
              map['superclass']?.toString() ?? map['extends']?.toString(),
          interfaces: _stringList(map['interfaces'] ?? map['implements']),
          mixins: _stringList(map['mixins'] ?? map['with']),
          kind: isClass ? map['kind']?.toString() : null,
          abstract: map['abstract'] == true,
        ),
      );
    }
    items.sort((a, b) => a.key.compareTo(b.key));
    return items;
  }

  List<AstMethodData> _parseMethods(Object? value) {
    if (value is! Map) return [];
    final items = <AstMethodData>[];
    for (final entry in value.entries) {
      final map = entry.value as Map<dynamic, dynamic>;
      final className = map['class']?.toString();
      final name = map['name']?.toString() ?? '';
      items.add(
        AstMethodData(
          key: entry.key.toString(),
          name: name,
          file: map['file']?.toString() ?? '',
          className:
              (className == null || className.isEmpty) ? null : className,
          callees: _stringList(map['callees']),
          callers: _stringList(map['callers']),
          isStatic: map['static'] == true,
          isConstructor: className != null && name == className,
        ),
      );
    }
    items.sort((a, b) => a.key.compareTo(b.key));
    return items;
  }

  Map<String, AstInheritanceData> _parseInheritance(Object? value) {
    if (value is! Map) return {};
    final result = <String, AstInheritanceData>{};
    for (final entry in value.entries) {
      final map = entry.value as Map<dynamic, dynamic>;
      result[entry.key.toString()] = AstInheritanceData(
        name: map['name']?.toString() ?? '',
        extendsType: map['extends']?.toString(),
        implementsTypes: _stringList(map['implements']),
        mixinTypes: _stringList(map['with']),
      );
    }
    return result;
  }

  List<AstStorageAccessData> _parseStorage(Object? value) {
    if (value is! List) return [];
    final items = <AstStorageAccessData>[];
    for (final item in value) {
      if (item is! Map) continue;
      items.add(
        AstStorageAccessData(
          file: item['file']?.toString() ?? '',
          method: item['method']?.toString() ?? '',
          target: item['target']?.toString() ?? '',
          kind: item['kind']?.toString(),
          line: item['line'] as int?,
        ),
      );
    }
    items.sort((a, b) {
      final file = a.file.compareTo(b.file);
      if (file != 0) return file;
      final method = a.method.compareTo(b.method);
      if (method != 0) return method;
      return a.target.compareTo(b.target);
    });
    return items;
  }

  List<AstStorageAccessData> _parseHiveBoxes(Object? value) {
    if (value is! List) return [];
    final items = <AstStorageAccessData>[];
    for (final item in value) {
      if (item is String) {
        items.add(
          AstStorageAccessData(file: '', method: '', target: item),
        );
        continue;
      }
      if (item is Map) {
        items.add(
          AstStorageAccessData(
            file: item['file']?.toString() ?? '',
            method: item['method']?.toString() ?? '',
            target: item['target']?.toString() ?? '',
          ),
        );
      }
    }
    items.sort((a, b) => a.target.compareTo(b.target));
    return items;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return [];
    return value.map((e) => e.toString()).toList()..sort();
  }
}
