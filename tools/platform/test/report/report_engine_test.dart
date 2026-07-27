import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/report_id_factory.dart';
import 'package:masterpalm_platform/report/report_validator.dart';
import 'package:masterpalm_platform/report/renderers/html_report_renderer.dart';
import 'package:masterpalm_platform/report/renderers/json_report_renderer.dart';
import 'package:masterpalm_platform/report/renderers/markdown_report_renderer.dart';
import 'package:masterpalm_platform/report/sources/ast_report_source.dart';

void main() {
  late Map<String, dynamic> astFixture;
  late Map<String, dynamic> guardianFixture;
  late Map<String, dynamic> guardianCleanFixture;

  setUp(() {
    astFixture = jsonDecode(
      File('test/fixtures/minimal_ast_report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    guardianFixture = jsonDecode(
      File('test/fixtures/minimal_guardian_analysis.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    guardianCleanFixture = jsonDecode(
      File('test/fixtures/guardian_no_violations.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  ReportEngine engine({
    AstProvider? astProvider,
    GraphProvider? graphProvider,
  }) {
    return ReportEngine(
      astProvider: astProvider,
      graphProvider: graphProvider,
      renderers: {
        ReportFormat.markdown: const MarkdownReportRenderer(),
        ReportFormat.json: const JsonReportRenderer(),
        ReportFormat.html: const HtmlReportRenderer(),
      },
    );
  }

  group('ReportDocument', () {
    test('is immutable and serializable', () {
      const doc = ReportDocument(
        metadata: ReportMetadata(
          reportId: 'report:test:architectureSummary:fp',
          reportType: ReportType.architectureSummary,
          reportSchemaVersion: 1,
          projectId: 'test',
          generatorVersion: ReportMetadata.defaultGeneratorVersion,
        ),
        sections: [
          ReportSection(
            id: 's1',
            title: 'Summary',
            blocks: [TextBlock(text: 'hello')],
          ),
        ],
      );
      final roundTrip = ReportDocument.fromJson(doc.toJson());
      expect(roundTrip.metadata.reportId, doc.metadata.reportId);
      expect(roundTrip.sections.length, 1);
    });
  });

  group('ReportIdFactory', () {
    const factory = ReportIdFactory();

    test('produces deterministic reportId', () {
      final fp = factory.fingerprintFromParts(['p', 'ast:1:2']);
      final id = factory.create(
        projectId: 'demo',
        reportType: ReportType.architectureSummary,
        sourceFingerprint: fp,
      );
      expect(id, 'report:demo:architectureSummary:ast:1:2|p');
    });
  });

  group('ReportValidator', () {
    const validator = ReportValidator();

    test('accepts valid document', () {
      final doc = _sampleDocument();
      final result = validator.validate(doc);
      expect(result.isValid, isTrue);
      expect(result.sectionCount, greaterThan(0));
    });

    test('detects duplicate section id', () {
      final doc = ReportDocument(
        metadata: _sampleMetadata(),
        sections: [
          ReportSection(id: 'dup', title: 'A', blocks: [TextBlock(text: 'a')]),
          ReportSection(id: 'dup', title: 'B', blocks: [TextBlock(text: 'b')]),
        ],
      );
      final result = validator.validate(doc);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Duplicate')), isTrue);
    });

    test('detects invalid table', () {
      final doc = ReportDocument(
        metadata: _sampleMetadata(),
        sections: [
          ReportSection(
            id: 'table',
            title: 'Table',
            blocks: [
              TableBlock(
                table: ReportTable(
                  columns: const [
                    ReportTableColumn(id: 'a', label: 'A'),
                    ReportTableColumn(id: 'b', label: 'B'),
                  ],
                  rows: [
                    ReportTableRow(cells: ['only-one'])
                  ],
                ),
              ),
            ],
          ),
        ],
      );
      final result = validator.validate(doc);
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('incompatible cell count')),
        isTrue,
      );
    });
  });

  group('ReportEngine generation', () {
    test('architectureSummary with AST only', () async {
      final result = await engine().generate(
        ReportRequest(
          reportType: ReportType.architectureSummary,
          projectId: 'demo',
          astReport: astFixture,
        ),
      );
      expect(result.status, ReportStatus.warning);
      expect(
          result.document.sections.any((s) => s.id == 'ast-summary'), isTrue);
    });

    test('guardianAnalysis requires guardian data', () async {
      final provider = PlatformReportProvider(engine: engine());
      final result = await provider.generate(
        ReportRequest(
          reportType: ReportType.guardianAnalysis,
          projectId: 'demo',
        ),
      );
      expect(result.status, ReportStatus.error);
      expect(result.errors.first, contains('Guardian source is required'));
    });

    test('guardianAnalysis succeeds with injected data', () async {
      final result = await engine().generate(
        ReportRequest(
          reportType: ReportType.guardianAnalysis,
          projectId: 'demo',
          guardianAnalysis: guardianFixture,
        ),
      );
      expect(result.status, ReportStatus.success);
      expect(
        result.document.sections.any((s) => s.id == 'guardian-overview'),
        isTrue,
      );
    });

    test('graphSummary with empty graph', () async {
      final graph = ProjectGraph(
        nodes: const [],
        edges: const [],
        metadata: const GraphMetadata(graphSchemaVersion: 1, source: 'test'),
      );
      final result = await engine().generate(
        ReportRequest(
          reportType: ReportType.graphSummary,
          projectId: 'demo',
          projectGraph: graph.toJson(),
        ),
      );
      expect(result.status, ReportStatus.success);
      expect(result.document.sections.first.id, 'graph-summary');
      final textBlocks =
          result.document.sections.first.blocks.whereType<TextBlock>().toList();
      expect(textBlocks.first.text, contains('Nodes: 0'));
    });

    test('combinedEngineeringReport requires all sources', () async {
      final provider = PlatformReportProvider(engine: engine());
      final result = await provider.generate(
        ReportRequest(
          reportType: ReportType.combinedEngineeringReport,
          projectId: 'demo',
          astReport: astFixture,
        ),
      );
      expect(result.status, ReportStatus.error);
    });

    test('combinedEngineeringReport with all fixtures', () async {
      final graph = GraphEngine().buildFromAstReport(astFixture);
      final result = await engine().generate(
        ReportRequest(
          reportType: ReportType.combinedEngineeringReport,
          projectId: 'demo',
          astReport: astFixture,
          guardianAnalysis: guardianFixture,
          projectGraph: graph.toJson(),
        ),
      );
      expect(result.status, ReportStatus.success);
      expect(result.document.sections.length, greaterThan(2));
    });

    test('optional graph missing yields warning for architectureSummary',
        () async {
      final result = await engine().generate(
        ReportRequest(
          reportType: ReportType.architectureSummary,
          projectId: 'demo',
          astReport: astFixture,
        ),
      );
      expect(result.warnings.any((w) => w.contains('Graph')), isTrue);
    });

    test('guardian without violations', () async {
      final result = await engine().generate(
        ReportRequest(
          reportType: ReportType.guardianAnalysis,
          projectId: 'demo',
          guardianAnalysis: guardianCleanFixture,
        ),
      );
      expect(result.status, ReportStatus.success);
      expect(result.document.metadata.reportId, isNotEmpty);
    });

    test('NO-GO decision is preserved', () async {
      final result = await engine().generate(
        ReportRequest(
          reportType: ReportType.guardianAnalysis,
          projectId: 'demo',
          guardianAnalysis: guardianFixture,
        ),
      );
      final decisions = result.document.sections
          .expand((s) => s.blocks)
          .whereType<DecisionBlock>()
          .toList();
      expect(decisions.first.decision, 'noGo');
    });

    test('special characters in content', () async {
      final payload = Map<String, dynamic>.from(guardianFixture);
      payload['summary'] = 'Pipe | test & <html> "quotes"';
      final md = await engine().generate(
        ReportRequest(
          reportType: ReportType.guardianAnalysis,
          projectId: 'demo',
          format: ReportFormat.markdown,
          guardianAnalysis: payload,
        ),
      );
      expect(md.rendered, contains('Pipe'));
      final html = engine().render(md.document, ReportFormat.html);
      expect(html, contains('&amp;'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('http://')));
    });
  });

  group('Renderers', () {
    test('markdown escapes table pipes', () {
      final doc = ReportDocument(
        metadata: _sampleMetadata(),
        sections: [
          ReportSection(
            id: 't',
            title: 'T',
            blocks: [
              TableBlock(
                table: ReportTable(
                  columns: const [
                    ReportTableColumn(id: 'c', label: 'Col'),
                  ],
                  rows: [
                    ReportTableRow(cells: ['a|b'])
                  ],
                ),
              ),
            ],
          ),
        ],
      );
      final md = const MarkdownReportRenderer().render(doc);
      expect(md, contains(r'a\|b'));
      expect(md.endsWith('\n'), isTrue);
    });

    test('json round-trip', () {
      final doc = _sampleDocument();
      final json = const JsonReportRenderer().render(doc);
      final decoded = ReportDocument.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(decoded.toComparableJson(), doc.toComparableJson());
    });

    test('html is offline-safe', () {
      final doc = _sampleDocument();
      final html = const HtmlReportRenderer().render(doc);
      expect(html.startsWith('<!DOCTYPE html>'), isTrue);
      expect(html.contains('charset="utf-8"'), isTrue);
      expect(html.contains('cdn'), isFalse);
      expect(html.contains('<script'), isFalse);
    });
  });

  group('Determinism', () {
    test('same input yields same document', () async {
      final request = ReportRequest(
        reportType: ReportType.guardianAnalysis,
        projectId: 'demo',
        guardianAnalysis: guardianFixture,
      );
      final a = await engine().generate(request);
      final b = await engine().generate(request);
      expect(a.document.toComparableJson(), b.document.toComparableJson());
    });

    test('same input yields same markdown/json/html', () async {
      final request = ReportRequest(
        reportType: ReportType.combinedEngineeringReport,
        projectId: 'demo',
        astReport: astFixture,
        guardianAnalysis: guardianFixture,
        projectGraph: GraphEngine().buildFromAstReport(astFixture).toJson(),
      );
      final eng = engine();
      final r1 = await eng.generate(request);
      final r2 = await eng.generate(request);
      for (final format in ReportFormat.values) {
        expect(
            eng.render(r1.document, format), eng.render(r2.document, format));
      }
    });
  });

  group('Platform integration', () {
    test('ReportProvider registers and resolves', () {
      final registry = ProviderRegistry();
      final config = PlatformConfig.forRepo('.');
      final core =
          PlatformBootstrap.forRepo('.', config: config, registry: registry);
      expect(core.report(), isA<PlatformReportProvider>());
      expect(core.report().supportedFormats, contains(ReportFormat.markdown));
    });

    test('PlatformCore.report generates via AstProvider', () async {
      final registry = ProviderRegistry();
      registry.registerInstance<AstProvider>(_FakeAstProvider(astFixture));
      final core = PlatformBootstrap.forRepo('.', registry: registry);
      final result = await core.report().generate(
            ReportRequest(
              reportType: ReportType.architectureSummary,
              projectId: 'demo',
            ),
          );
      expect(
          result.document.sections.any((s) => s.id == 'ast-summary'), isTrue);
    });

    test('AstProvider integration via source', () {
      const source = AstReportSource();
      final data = source.fromMap(astFixture);
      expect(data.totalClasses, greaterThan(0));
    });

    test('GuardianProvider data via source', () {
      const source = GuardianReportSource();
      final data = source.fromMap(guardianFixture);
      expect(data.decision, 'noGo');
      expect(data.violations.length, 1);
    });

    test('GraphProvider integration', () async {
      final graph = GraphEngine().buildFromAstReport(astFixture);
      final provider = InMemoryGraphProvider();
      await provider.publish(graph);
      const source = GraphReportSource();
      final data = await source.fromProvider(provider);
      expect(data!.nodeCount, graph.nodes.length);
    });
  });

  group('Legacy Guardian structural equivalence', () {
    test('preserves decision and violation codes', () {
      const source = GuardianReportSource();
      final data = source.fromMap(guardianFixture);
      expect(data.decision, guardianFixture['decision']);
      expect(data.violations.first['code'], 'G001');
      expect(data.riskOverall, 'red');
      expect(data.requiredTests, isNotEmpty);
    });
  });
}

ReportMetadata _sampleMetadata() {
  return const ReportMetadata(
    reportId: 'report:demo:architectureSummary:test',
    reportType: ReportType.architectureSummary,
    reportSchemaVersion: 1,
    projectId: 'demo',
    generatorVersion: ReportMetadata.defaultGeneratorVersion,
  );
}

ReportDocument _sampleDocument() {
  return ReportDocument(
    metadata: _sampleMetadata(),
    sections: [
      ReportSection(
        id: 'summary',
        title: 'Summary',
        blocks: [
          const HeadingBlock(level: 1, text: 'Report'),
          const SummaryBlock(text: 'Stable summary'),
          const TextBlock(text: 'Details'),
        ],
      ),
    ],
  );
}

class _FakeAstProvider implements AstProvider {
  _FakeAstProvider(this._report);

  final Map<String, dynamic> _report;

  @override
  String get reportPath => '/tmp/ast_report.json';

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
