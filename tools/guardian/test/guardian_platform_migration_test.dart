import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/diff_analyzer.dart';
import '../lib/guardian_platform_bootstrap.dart';
import '../lib/mappers/guardian_platform_mappers.dart';
import '../lib/models/guardian_result.dart';
import '../lib/models/impact_result.dart';
import '../lib/models/risk_result.dart';
import '../lib/providers/guardian_engine_provider.dart';

void main() {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));

  GuardianSession bootstrap([AstProvider? ast]) {
    return GuardianPlatformBootstrap.create(
      repoRoot: repoRoot,
      astProvider: ast,
    );
  }

  group('GuardianPlatformBootstrap', () {
    test('registers and resolves GuardianProvider', () {
      final session = bootstrap();
      expect(session.platform.guardian(), isA<GuardianEngineProvider>());
      expect(identical(session.provider, session.platform.guardian()), isTrue);
    });

    test('loads GuardianConfig once and injects into engine', () {
      final session = bootstrap();
      expect(identical(session.config, session.engine.config), isTrue);
    });

    test('fails clearly when AstProvider is missing', () {
      expect(
        () => GuardianPlatformBootstrap.create(
          repoRoot: repoRoot,
          registry: ProviderRegistry(),
          registerDefaultAst: false,
        ),
        throwsA(isA<ProviderException>()),
      );
    });

    test('uses AstProvider interface without FileSystemAstProvider in engine',
        () {
      final fake = _FakeAstProvider();
      final session = bootstrap(fake);
      expect(session.engine.ast, same(fake));
    });
  });

  group('Guardian mappers', () {
    test('maps impact and risk to platform DTOs', () {
      final impact = ImpactResult(domains: ['Estoque'], services: ['a.dart']);
      final risk = RiskResult(
        overall: RiskLevel.red,
        items: [
          RiskItem(
              file: 'lib/a.dart', level: RiskLevel.red, reason: 'critical'),
        ],
      );

      final change = GuardianPlatformMappers.toChangeImpact(impact);
      expect(change.domains, ['Estoque']);

      final platformRisk = GuardianPlatformMappers.toPlatformRisk(risk);
      expect(platformRisk.overall, PlatformRiskLevel.high);
    });
  });

  group('Legacy vs Platform equivalence', () {
    Future<GuardianResult> enginePath(DiffAnalysis diff) async {
      final session = bootstrap();
      return session.engine.analyze(injectedDiff: diff);
    }

    Future<GuardianResult> providerPath(DiffAnalysis diff) async {
      final session = bootstrap();
      final request = GuardianAnalysisRequest(
        context: AnalysisContext(
          project: PlatformBootstrap.projectFromRepo(repoRoot),
          snapshot: PlatformSnapshot.fresh(),
        ),
      );
      final provider = session.platform.guardian() as GuardianEngineProvider;
      return provider.analyzeGuardian(request, injectedDiff: diff);
    }

    final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/services/estoque_transaction_service.dart b/lib/services/estoque_transaction_service.dart
--- a/lib/services/estoque_transaction_service.dart
+++ b/lib/services/estoque_transaction_service.dart
@@ -1 +1 @@
+  // change
''');

    test('engine and provider produce equivalent decisions', () async {
      final engineResult = await enginePath(diff);
      final providerResult = await providerPath(diff);

      expect(providerResult.decision, engineResult.decision);
      expect(providerResult.risk.overall, engineResult.risk.overall);
      expect(providerResult.impact.domains, engineResult.impact.domains);
      expect(
        providerResult.violations.map((v) => v.code).toList(),
        engineResult.violations.map((v) => v.code).toList(),
      );
      expect(
        providerResult.requiredTests,
        engineResult.requiredTests,
      );
    });

    test('AnalysisResult mapper preserves decision and summary', () async {
      final providerResult = await providerPath(diff);
      final mapped = GuardianPlatformMappers.toAnalysisResult(providerResult);
      expect(mapped.success, providerResult.decision == GuardianDecision.go);
      expect(mapped.summary, providerResult.summary);
      expect(
        mapped.details['decision'],
        providerResult.decision.name,
      );
    });
  });

  group('Architecture constraints', () {
    test('guardian lib does not reference ast_report.json', () {
      final libDir = Directory(p.join(repoRoot, 'tools', 'guardian', 'lib'));
      final violations = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (content.contains('ast_report.json')) {
          violations.add(p.relative(entity.path, from: repoRoot));
        }
        if (content.contains('FileSystemAstProvider')) {
          violations.add(
              '${p.relative(entity.path, from: repoRoot)}: FileSystemAstProvider');
        }
      }
      expect(violations, isEmpty, reason: violations.join(', '));
    });
  });
}

class _FakeAstProvider implements AstProvider {
  @override
  String get reportPath => '/tmp/fake_ast_report.json';

  @override
  Map<String, dynamic> loadReport() => {};

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
