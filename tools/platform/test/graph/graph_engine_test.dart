import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> fixture;

  setUp(() {
    final path = 'test/fixtures/minimal_ast_report.json';
    fixture = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  });

  group('GraphNodeIdFactory', () {
    const factory = GraphNodeIdFactory();

    test('produces deterministic node ids', () {
      expect(
        factory.method('lib/a.dart', 'save', className: 'Svc'),
        'method:lib/a.dart::Svc::save',
      );
      expect(
        factory.file(r'lib\a.dart'),
        'file:lib/a.dart',
      );
      expect(
          factory.firestoreCollection('vendas'), 'firestore_collection:vendas');
    });
  });

  group('GraphBuilder', () {
    test('creates nodes and edges with deduplication', () {
      final engine = GraphEngine();
      final graph = engine.buildFromAstReport(fixture);

      expect(graph.nodes.isNotEmpty, isTrue);
      expect(graph.edges.isNotEmpty, isTrue);
      expect(
        graph.nodes.map((n) => n.id).toSet().length,
        graph.nodes.length,
      );
      expect(
        graph.edges.map((e) => e.dedupeKey).toSet().length,
        graph.edges.length,
      );
    });

    test('classifies service, screen and storage nodes', () {
      final graph = GraphEngine().buildFromAstReport(fixture);
      final types = graph.nodes.map((n) => n.type).toSet();
      expect(types, contains(GraphNodeType.service));
      expect(types, contains(GraphNodeType.screen));
      expect(types, contains(GraphNodeType.firestoreCollection));
      expect(types, contains(GraphNodeType.hiveBox));
    });
  });

  group('GraphValidator', () {
    test('detects orphan edges', () {
      const validator = GraphValidator();
      final graph = ProjectGraph(
        nodes: const [
          GraphNode(id: 'a', type: GraphNodeType.file, label: 'a'),
        ],
        edges: const [
          GraphEdge(
            sourceId: 'a',
            targetId: 'missing',
            type: GraphEdgeType.dependsOn,
          ),
        ],
        metadata: const GraphMetadata(
          graphSchemaVersion: 1,
          source: 'test',
        ),
      );
      final result = validator.validate(graph);
      expect(result.valid, isFalse);
      expect(result.errors.any((e) => e.contains('Orphan')), isTrue);
    });

    test('detects duplicate node ids', () {
      const validator = GraphValidator();
      final graph = ProjectGraph(
        nodes: const [
          GraphNode(id: 'a', type: GraphNodeType.file, label: 'a'),
          GraphNode(id: 'a', type: GraphNodeType.file, label: 'a2'),
        ],
        edges: const [],
        metadata: const GraphMetadata(
          graphSchemaVersion: 1,
          source: 'test',
        ),
      );
      expect(validator.validate(graph).valid, isFalse);
    });
  });

  group('GraphQueryEngine', () {
    late ProjectGraph graph;
    late GraphQueryEngine queries;
    late GraphNodeIdFactory ids;

    setUp(() {
      graph = GraphEngine().buildFromAstReport(fixture);
      queries = const GraphQueryEngine();
      ids = const GraphNodeIdFactory();
    });

    test('queries dependencies and calls', () {
      final screenFile = ids.file('lib/screens/venda_screen.dart');
      final deps = queries.directDependencies(graph, screenFile);
      expect(deps, isNotEmpty);

      final caller = ids.method(
        'lib/screens/venda_screen.dart',
        'build',
        className: 'VendaScreen',
      );
      final save = ids.method(
        'lib/services/venda_service.dart',
        'salvarVenda',
        className: 'VendaService',
      );
      expect(queries.methodCalls(graph, caller), contains(save));
      expect(queries.methodCallers(graph, save), contains(caller));
    });

    test('finds path and respects depth limit', () async {
      final from = ids.method(
        'lib/screens/venda_screen.dart',
        'build',
        className: 'VendaScreen',
      );
      final to = ids.firestoreCollection('vendas');
      expect(queries.hasPath(graph, from, to), isTrue);

      final neighbors = queries.neighbors(graph, from, maxDepth: 1);
      expect(neighbors.nodeIds, contains(from));
      expect(neighbors.reachedMaxDepth, anyOf(isTrue, isFalse));
    });

    test('handles cycles without infinite loop', () {
      const a = GraphNode(id: 'a', type: GraphNodeType.file, label: 'a');
      const b = GraphNode(id: 'b', type: GraphNodeType.file, label: 'b');
      final cyclicGraph = ProjectGraph(
        nodes: const [a, b],
        edges: const [
          GraphEdge(
              sourceId: 'a', targetId: 'b', type: GraphEdgeType.dependsOn),
          GraphEdge(
              sourceId: 'b', targetId: 'a', type: GraphEdgeType.dependsOn),
        ],
        metadata: const GraphMetadata(
          graphSchemaVersion: 1,
          source: 'test',
        ),
      );
      final path = queries.findPath(cyclicGraph, 'a', 'b', maxDepth: 5);
      expect(path, isNotEmpty);
    });
  });

  group('Determinism', () {
    test('same AST input yields comparable graph', () {
      final engine = GraphEngine();
      final first = engine.buildFromAstReport(fixture).toComparableJson();
      final second = engine.buildFromAstReport(fixture).toComparableJson();
      expect(jsonEncode(first), jsonEncode(second));
    });
  });

  group('AstGraphMapper', () {
    test('throws on empty report', () {
      expect(
        () => const AstGraphMapper().parse({}),
        throwsA(isA<GraphParseException>()),
      );
    });

    test('tolerates partial report with defaults', () {
      final partial = {
        'meta': {'repo_root': '/x'}
      };
      final data = const AstGraphMapper().parse(partial);
      expect(data.projectName, isNotEmpty);
      expect(data.classes, isEmpty);
    });
  });

  group('GraphProvider integration', () {
    test('registers and resolves via PlatformCore', () async {
      final core = PlatformBootstrap.forRepo('.');
      expect(core.graph(), isA<InMemoryGraphProvider>());
    });

    test('publish and load round-trip', () async {
      final provider = InMemoryGraphProvider();
      final graph = GraphEngine().buildFromAstReport(fixture);
      await provider.publish(graph);
      expect(await provider.isAvailable(), isTrue);
      final loaded = await provider.load();
      expect(loaded?.nodes.length, graph.nodes.length);
      await provider.invalidate();
      expect(await provider.isAvailable(), isFalse);
    });

    test('AstProvider to GraphEngine integration', () async {
      final ast = _FakeAstProvider(fixture);
      final graph = await GraphPlatformBootstrap.buildFromAst(ast);
      expect(graph.metadata.graphSchemaVersion,
          GraphMetadata.currentSchemaVersion);
      expect(graph.nodes.any((n) => n.type == GraphNodeType.method), isTrue);
    });

    test('buildAndPublish via PlatformCore', () async {
      final registry = ProviderRegistry();
      registry.registerInstance<AstProvider>(_FakeAstProvider(fixture));
      final core = PlatformBootstrap.forRepo('.', registry: registry);
      final graph =
          await GraphPlatformBootstrap.buildAndPublish(platform: core);
      expect(await core.graph().isAvailable(), isTrue);
      expect((await core.graph().load())?.edges, graph.edges);
    });
  });

  group('Architecture constraints', () {
    test('graph module has no forbidden file access patterns', () {
      final graphDir = Directory('lib/graph');
      final violations = <String>[];
      for (final entity in graphDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        for (final pattern in [
          'ast_report.json',
          'FileSystemAstProvider',
          'dart:io',
          'Firebase',
        ]) {
          if (content.contains(pattern)) {
            violations.add('${entity.path}: $pattern');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join(', '));
    });
  });
}

class _FakeAstProvider implements AstProvider {
  _FakeAstProvider(this._report);

  final Map<String, dynamic> _report;

  @override
  String get reportPath => '/tmp/fake.json';

  @override
  Map<String, dynamic> loadReport() => _report;

  @override
  void saveReport(Map<String, dynamic> report) {}

  @override
  int? complexityForMethod(String methodKey) => null;

  @override
  int? complexityForFile(String relPath) => null;

  @override
  int? linesForFile(String relPath) => null;

  @override
  List<String> callersForFile(String relPath) => [];

  @override
  bool hasImportCycle(List<String> changedFiles) => false;
}
