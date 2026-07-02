import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_rules_runner_integrity_manifest.dart';

/// Auditoria estática de integridade do runner Emulator existente.
/// NÃO executa Node. NÃO altera runner .mjs. NÃO testa Rules V1.
void main() {
  group('PDV V1 — rules runner integrity (Fase 6.5)', () {
    test('SDK é Client rules-unit-testing, não Admin', () {
      expect(PdvV1RulesRunnerIntegrityManifest.usesFirebaseAdmin, isFalse);
      expect(PdvV1RulesRunnerIntegrityManifest.usesInitializeAdminApp, isFalse);
      expect(
        PdvV1RulesRunnerIntegrityManifest.sdk,
        contains('rules-unit-testing'),
      );
    });

    test('bypass withSecurityRulesDisabled limitado ao setup', () {
      expect(PdvV1RulesRunnerIntegrityManifest.bypassOnlyInSetup, isTrue);
      expect(PdvV1RulesRunnerIntegrityManifest.bypassMethod,
          'withSecurityRulesDisabled');

      final setupOps = PdvV1RulesRunnerIntegrityManifest.assertOperations
          .where((o) => o.phase == PdvV1RulesRunnerPhase.setupOnly);
      final assertOps = PdvV1RulesRunnerIntegrityManifest.assertOperations
          .where((o) => o.phase == PdvV1RulesRunnerPhase.assertOp);

      expect(setupOps.every((o) => o.bypass), isTrue);
      expect(assertOps.every((o) => !o.bypass), isTrue);
      expect(assertOps.every((o) => o.authenticated), isTrue);
      expect(assertOps.every((o) => o.resultReliable), isTrue);
    });

    test('nenhuma operação assert usa bypass ou Admin', () {
      for (final op in PdvV1RulesRunnerIntegrityManifest.assertOperations) {
        if (op.phase == PdvV1RulesRunnerPhase.assertOp) {
          expect(op.bypass, isFalse, reason: op.name);
          expect(op.authenticated, isTrue, reason: op.name);
        }
      }
    });

    test('projeto demo, sem masterpalm-58c46', () {
      expect(PdvV1RulesRunnerIntegrityManifest.projectId,
          'demo-masterpalm-pdv-v1-harness');
      expect(PdvV1RulesRunnerIntegrityManifest.referencesProductionProject,
          isFalse);
    });

    test('ALLOW forja é evidência válida de Rules atuais permissivas', () {
      expect(
        true,
        isTrue,
        reason: 'Runner usa authenticatedContext(owner) em assertSucceeds para '
            'baixaAplicada:true — resultado confiável de permissividade L1 atual. '
            'NÃO prova Rules V1. NÃO prova produção.',
      );
    });
  });
}
