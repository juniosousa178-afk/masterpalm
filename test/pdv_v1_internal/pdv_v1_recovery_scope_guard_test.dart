import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_orchestrator.dart';

void main() {
  final orchestrator = PdvV1RecoveryOrchestrator();

  group('PdvV1Recovery scope guard', () {
    test('orquestrador não expõe parâmetros de callback executável', () {
      final planMethod = PdvV1RecoveryOrchestrator().plan;
      expect(planMethod.runtimeType.toString(),
          contains('PdvV1RecoveryOrchestratorInput'));
      expect(
        orchestrator.plan(const PdvV1RecoveryOrchestratorInput()).decision,
        isA<PdvV1RecoveryDecision>(),
      );
    });

    test(
        'nenhum arquivo lib recovery usa Firebase, Hive.openBox ou DateTime.now',
        () async {
      final dir = Directory('lib/services/pdv_v1_internal');
      final forbidden = [
        'FirebaseFirestore',
        'FirebaseAuth',
        'runTransaction',
        'Hive.openBox',
        'SharedPreferences',
        'DateTime.now',
        'Uuid',
        'package:uuid',
        'BuildContext',
        'package:flutter/material',
        'package:flutter/widgets',
        'void Function',
        'Future<void> Function',
      ];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (!entity.path.contains('pdv_v1_recovery')) continue;
        final content = await entity.readAsString();
        for (final token in forbidden) {
          expect(
            content.contains(token),
            isFalse,
            reason: '${entity.path} não deve conter $token',
          );
        }
      }
    });

    test('nenhum call site de produção referencia recovery', () async {
      final roots = [
        Directory('lib/screens'),
        Directory('lib/services'),
      ];
      final hits = <String>[];
      final tokens = [
        'pdv_v1_recovery',
        'PdvV1RecoveryOrchestrator',
        'PdvV1RemoteVerificationEvidence',
      ];
      for (final root in roots) {
        if (!await root.exists()) continue;
        await for (final entity in root.list(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('pdv_v1_internal')) continue;
          final content = await entity.readAsString();
          for (final token in tokens) {
            if (content.contains(token)) hits.add('${entity.path}:$token');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });

    test('decisões não criam UUID, Firebase ou Hive', () {
      final plan = orchestrator.plan(const PdvV1RecoveryOrchestratorInput());
      final json = plan.toJson();
      final encoded = json.toString();
      expect(encoded.contains('Firebase'), isFalse);
      expect(encoded.contains('Hive.openBox'), isFalse);
      expect(encoded.contains('Uuid'), isFalse);
    });
  });
}
