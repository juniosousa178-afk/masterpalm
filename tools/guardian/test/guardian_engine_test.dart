import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/diff_analyzer.dart';
import '../lib/guardian_platform_bootstrap.dart';
import '../lib/models/guardian_result.dart';
import '../lib/models/risk_result.dart';
import '../lib/providers/guardian_engine_provider.dart';
import 'package:masterpalm_platform/masterpalm_platform.dart';

void main() {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));

  GuardianEngineProvider provider() {
    return GuardianPlatformBootstrap.create(repoRoot: repoRoot)
        .platform
        .guardian() as GuardianEngineProvider;
  }

  GuardianAnalysisRequest request() {
    return GuardianAnalysisRequest(
      context: AnalysisContext(
        project: PlatformBootstrap.projectFromRepo(repoRoot),
        snapshot: PlatformSnapshot.fresh(),
      ),
    );
  }

  group('GuardianEngine scenarios', () {
    test('1. visual change only — VERDE/GO', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/widgets/my_button.dart b/lib/widgets/my_button.dart
--- a/lib/widgets/my_button.dart
+++ b/lib/widgets/my_button.dart
@@ -1 +1 @@
-  color: Colors.red,
+  color: Colors.blue,
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.risk.overall, RiskLevel.green);
      expect(result.decision, GuardianDecision.go);
    });

    test('2. EstoqueTransactionService change — VERMELHO', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/services/estoque_transaction_service.dart b/lib/services/estoque_transaction_service.dart
--- a/lib/services/estoque_transaction_service.dart
+++ b/lib/services/estoque_transaction_service.dart
@@ -1 +1 @@
+  // risky change to baixarEstoqueTransactionBatchIdempotente
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.impact.domains, contains('Estoque'));
      expect(result.risk.overall, RiskLevel.red);
    });

    test('3. CAS removal — BLOQUEANTE', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/services/estoque_transaction_service.dart b/lib/services/estoque_transaction_service.dart
--- a/lib/services/estoque_transaction_service.dart
+++ b/lib/services/estoque_transaction_service.dart
@@ -1 +1 @@
-    final operationId = marker.operationId;
''');
      expect(diff.casWeakened || diff.idempotencyWeakened, isTrue);
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.violations.any((v) => v.code == 'G012'), isTrue);
      expect(result.decision, GuardianDecision.noGo);
    });

    test('4. new import cycle — BLOQUEANTE', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/core/effective_plan_access.dart b/lib/core/effective_plan_access.dart
--- a/lib/core/effective_plan_access.dart
+++ b/lib/core/effective_plan_access.dart
@@ -1 +1 @@
+import 'package:master_palm/services/planos_service.dart';
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.violations.any((v) => v.code == 'G008'), isTrue);
      expect(result.decision, GuardianDecision.noGo);
    });

    test('5. firestore rules — G009', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/firestore.rules b/firestore.rules
--- a/firestore.rules
+++ b/firestore.rules
@@ -1 +1 @@
+  allow read: if true;
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.violations.any((v) => v.code == 'G009'), isTrue);
    });

    test('6. sync + hive — G005 domain', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/services/sync_queue_service.dart b/lib/services/sync_queue_service.dart
--- a/lib/services/sync_queue_service.dart
+++ b/lib/services/sync_queue_service.dart
@@ -1 +1 @@
+  await Hive.openBox('sync_queue');
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.impact.domains, contains('Sync'));
      expect(result.impact.domains, contains('Hive'));
    });

    test('8. docs only — VERDE', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/docs/knowledge/INDEX.md b/docs/knowledge/INDEX.md
--- a/docs/knowledge/INDEX.md
+++ b/docs/knowledge/INDEX.md
@@ -1 +1 @@
+updated
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.decision, GuardianDecision.go);
    });

    test('9. repair script without dry-run — BLOQUEANTE', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/tools/maintenance/repair_test.mjs b/tools/maintenance/repair_test.mjs
--- a/tools/maintenance/repair_test.mjs
+++ b/tools/maintenance/repair_test.mjs
@@ -1 +1 @@
+await applyRepair();
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.violations.any((v) => v.code == 'G013'), isTrue);
      expect(result.decision, GuardianDecision.noGo);
    });

    test('10. lojaId change — tenant domain', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/services/loja_id_service.dart b/lib/services/loja_id_service.dart
--- a/lib/services/loja_id_service.dart
+++ b/lib/services/loja_id_service.dart
@@ -1 +1 @@
+  // change tenant resolution
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      expect(result.impact.domains, contains('Tenant'));
    });

    test('preserves G001–G015 rule codes on estoque change', () async {
      final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('''
diff --git a/lib/services/estoque_transaction_service.dart b/lib/services/estoque_transaction_service.dart
--- a/lib/services/estoque_transaction_service.dart
+++ b/lib/services/estoque_transaction_service.dart
@@ -1 +1 @@
+  // change
''');
      final result =
          await provider().analyzeGuardian(request(), injectedDiff: diff);
      final codes = result.violations.map((v) => v.code).toSet();
      expect(codes.contains('G001'), isTrue);
      for (final code in codes) {
        expect(RegExp(r'^G\d{3}$').hasMatch(code), isTrue);
      }
    });
  });
}
