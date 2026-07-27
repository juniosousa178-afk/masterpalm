import '../models/graph/graph_edge.dart';
import '../models/graph/graph_edge_type.dart';
import '../models/graph/graph_metadata.dart';
import '../models/graph/graph_node.dart';
import '../models/graph/graph_node_type.dart';
import '../models/graph/project_graph.dart';
import 'ast_graph_models.dart';
import 'graph_node_id_factory.dart';

/// Classification heuristics for AST-derived graph nodes.
class GraphNodeClassifier {
  const GraphNodeClassifier({this.enableScreenHeuristic = true});

  final bool enableScreenHeuristic;

  /// Maps AST `kind` to graph node type. Documented in Sprint 02.1 report.
  GraphNodeType classType(AstTypeData type) {
    switch (type.kind) {
      case 'widget':
        if (enableScreenHeuristic && _isScreenFile(type.file)) {
          return GraphNodeType.screen;
        }
        return GraphNodeType.widget;
      case 'service':
        return GraphNodeType.service;
      case 'repository':
        return GraphNodeType.repository;
      default:
        return GraphNodeType.clazz;
    }
  }

  bool _isScreenFile(String file) {
    final normalized = GraphNodeIdFactory.normalizePath(file);
    return normalized.startsWith('lib/screens/');
  }
}

/// Builds immutable [ProjectGraph] instances from typed AST DTOs.
class GraphBuilder {
  GraphBuilder({
    GraphNodeIdFactory? idFactory,
    GraphNodeClassifier? classifier,
  })  : _ids = idFactory ?? const GraphNodeIdFactory(),
        _classifier = classifier ?? const GraphNodeClassifier();

  final GraphNodeIdFactory _ids;
  final GraphNodeClassifier _classifier;

  final Map<String, GraphNode> _nodes = {};
  final Map<String, GraphEdge> _edges = {};

  ProjectGraph build(AstProjectData data) {
    _nodes.clear();
    _edges.clear();

    final projectId = _ids.project(data.projectName);
    _addNode(
      GraphNode(
        id: projectId,
        type: GraphNodeType.project,
        label: data.projectName,
        metadata: {
          if (data.projectRoot != null) 'root': data.projectRoot!,
        },
      ),
    );

    const packageName = 'master_palm';
    final packageId = _ids.package(packageName);
    _addNode(
      GraphNode(
        id: packageId,
        type: GraphNodeType.package,
        label: packageName,
      ),
    );
    _addEdge(projectId, packageId, GraphEdgeType.contains);

    for (final file in data.files) {
      _buildFileHierarchy(packageId, file.path);
    }

    for (final type in data.enums) {
      _buildEnum(type);
    }
    for (final type in data.extensions) {
      _buildExtension(type);
    }
    for (final type in data.mixins) {
      _buildMixin(type);
    }
    for (final type in data.classes) {
      _buildClass(type, data.inheritance[type.key]);
    }

    for (final method in data.methods) {
      _buildMethod(method);
    }

    _buildImports(data.importGraph);
    _buildCalls(data.methods);
    _buildFirestore(data);
    _buildHive(data.hiveBoxes);

    final nodes = _nodes.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    final edges = _edges.values.toList()
      ..sort((a, b) => a.dedupeKey.compareTo(b.dedupeKey));

    return ProjectGraph(
      nodes: nodes,
      edges: edges,
      metadata: GraphMetadata(
        graphSchemaVersion: GraphMetadata.currentSchemaVersion,
        source: 'masterpalm_ast_engine',
        projectRoot: data.projectRoot,
        generatedAt: data.generatedAt,
        nodeCount: nodes.length,
        edgeCount: edges.length,
      ),
    );
  }

  void _buildFileHierarchy(String packageId, String path) {
    final fileId = _ids.file(path);
    final libraryId = _ids.library(path);
    _addNode(GraphNode(id: fileId, type: GraphNodeType.file, label: path));
    _addNode(
      GraphNode(id: libraryId, type: GraphNodeType.library, label: path),
    );
    _addEdge(packageId, fileId, GraphEdgeType.contains);
    _addEdge(fileId, libraryId, GraphEdgeType.contains);
  }

  void _buildClass(AstTypeData type, AstInheritanceData? inheritance) {
    if (type.file.isEmpty) return;
    final fileId = _ids.file(type.file);
    final nodeType = _classifier.classType(type);
    final classId = _ids.classId(type.file, type.name);
    _addNode(
      GraphNode(
        id: classId,
        type: nodeType,
        label: type.name,
        metadata: {
          if (type.kind != null) 'astKind': type.kind!,
          'abstract': type.abstract.toString(),
        },
      ),
    );
    _addEdge(fileId, classId, GraphEdgeType.declares);

    final superType = inheritance?.extendsType ?? type.superclass;
    if (superType != null && superType.isNotEmpty) {
      final superId = _externalType(superType);
      _addEdge(classId, superId, GraphEdgeType.extendsType);
    }

    for (final iface in inheritance?.implementsTypes ?? type.interfaces) {
      final ifaceId = _externalType(iface);
      _addEdge(classId, ifaceId, GraphEdgeType.implementsType);
    }

    for (final mixinName in inheritance?.mixinTypes ?? type.mixins) {
      final mixinId = _ids.mixin(type.file, mixinName);
      if (_nodes.containsKey(mixinId)) {
        _addEdge(classId, mixinId, GraphEdgeType.mixesIn);
      } else {
        _addEdge(classId, _externalType(mixinName), GraphEdgeType.mixesIn);
      }
    }
  }

  void _buildEnum(AstTypeData type) {
    if (type.file.isEmpty) return;
    final id = _ids.enumType(type.file, type.name);
    _addNode(GraphNode(id: id, type: GraphNodeType.enumType, label: type.name));
    _addEdge(_ids.file(type.file), id, GraphEdgeType.declares);
  }

  void _buildExtension(AstTypeData type) {
    if (type.file.isEmpty) return;
    final id = _ids.extension(type.file, type.name);
    _addNode(
        GraphNode(id: id, type: GraphNodeType.extensionType, label: type.name));
    _addEdge(_ids.file(type.file), id, GraphEdgeType.declares);
  }

  void _buildMixin(AstTypeData type) {
    if (type.file.isEmpty) return;
    final id = _ids.mixin(type.file, type.name);
    _addNode(
        GraphNode(id: id, type: GraphNodeType.mixinType, label: type.name));
    _addEdge(_ids.file(type.file), id, GraphEdgeType.declares);
  }

  void _buildMethod(AstMethodData method) {
    if (method.file.isEmpty) return;
    final parentId = method.className == null
        ? _ids.file(method.file)
        : _ids.classId(method.file, method.className!);

    final nodeType = method.isConstructor
        ? GraphNodeType.constructor
        : (method.className == null
            ? GraphNodeType.function
            : GraphNodeType.method);

    final methodId = method.isConstructor
        ? _ids.constructor(method.file, method.className!)
        : _ids.method(
            method.file,
            method.name,
            className: method.className,
          );

    _addNode(
      GraphNode(
        id: methodId,
        type: nodeType,
        label: method.name,
        metadata: {
          'astKey': method.key,
          if (method.className != null) 'class': method.className!,
        },
      ),
    );
    _addEdge(parentId, methodId, GraphEdgeType.declares);
  }

  void _buildImports(Map<String, List<String>> importGraph) {
    for (final entry in importGraph.entries) {
      final source = _ids.file(entry.key);
      for (final targetPath in entry.value) {
        if (!targetPath.startsWith('lib/')) continue;
        final target = _ids.file(targetPath);
        if (!_nodes.containsKey(target)) {
          _addNode(
            GraphNode(id: target, type: GraphNodeType.file, label: targetPath),
          );
        }
        _addEdge(source, target, GraphEdgeType.imports);
        _addEdge(source, target, GraphEdgeType.dependsOn);
      }
    }
  }

  void _buildCalls(List<AstMethodData> methods) {
    final index = {for (final m in methods) m.key: m};
    for (final method in methods) {
      final callerId = _methodId(method);
      if (callerId == null) continue;
      for (final calleeKey in method.callees) {
        final callee = index[calleeKey];
        if (callee == null) continue;
        final calleeId = _methodId(callee);
        if (calleeId == null) continue;
        _addEdge(callerId, calleeId, GraphEdgeType.calls);
      }
    }
  }

  void _buildFirestore(AstProjectData data) {
    final methodIndex = {
      for (final m in data.methods) '${m.file}::${m.key}': m,
      for (final m in data.methods)
        if (m.className != null) '${m.file}::${m.className}.${m.name}': m,
    };

    _buildStorageAccess(
      data.firestoreWrites,
      GraphEdgeType.writesTo,
      methodIndex,
    );
    _buildStorageAccess(
      data.firestoreReads,
      GraphEdgeType.readsFrom,
      methodIndex,
    );
    _buildStorageAccess(
      data.firestoreTransactions,
      GraphEdgeType.accesses,
      methodIndex,
    );
  }

  void _buildStorageAccess(
    List<AstStorageAccessData> accesses,
    GraphEdgeType edgeType,
    Map<String, AstMethodData> methodIndex,
  ) {
    for (final access in accesses) {
      if (access.target.isEmpty || access.file.isEmpty) continue;
      final collectionId = _ids.firestoreCollection(access.target);
      _addNode(
        GraphNode(
          id: collectionId,
          type: GraphNodeType.firestoreCollection,
          label: access.target,
        ),
      );

      final method = methodIndex['${access.file}::${access.method}'];
      final sourceId =
          method != null ? _methodId(method) : _ids.file(access.file);
      if (sourceId == null) continue;
      _addEdge(sourceId, collectionId, edgeType);
    }
  }

  void _buildHive(List<AstStorageAccessData> hiveBoxes) {
    for (final access in hiveBoxes) {
      if (access.target.isEmpty) continue;
      final boxId = _ids.hiveBox(access.target);
      _addNode(
        GraphNode(
          id: boxId,
          type: GraphNodeType.hiveBox,
          label: access.target,
        ),
      );
      if (access.file.isEmpty) continue;
      final sourceId = _ids.file(access.file);
      _addEdge(sourceId, boxId, GraphEdgeType.accesses);
    }
  }

  String? _methodId(AstMethodData method) {
    if (method.file.isEmpty) return null;
    if (method.isConstructor && method.className != null) {
      return _ids.constructor(method.file, method.className!);
    }
    return _ids.method(method.file, method.name, className: method.className);
  }

  String _externalType(String name) {
    final id = _ids.externalType(name);
    _addNode(
      GraphNode(id: id, type: GraphNodeType.externalType, label: name),
    );
    return id;
  }

  void _addNode(GraphNode node) {
    _nodes.putIfAbsent(node.id, () => node);
  }

  void _addEdge(String sourceId, String targetId, GraphEdgeType type,
      {String? context}) {
    if (sourceId.isEmpty || targetId.isEmpty) return;
    final edge = GraphEdge(
      sourceId: sourceId,
      targetId: targetId,
      type: type,
      context: context,
    );
    _edges.putIfAbsent(edge.dedupeKey, () => edge);
  }
}
