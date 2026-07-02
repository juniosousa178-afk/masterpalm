import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _allowedExternalAdapterPath = File(
  'lib/services/pdv_v1_infrastructure/'
  'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
).absolute.path.replaceAll('\\', '/');

bool isExactAllowedExternalAdapter(File entity) {
  final entityPath = entity.absolute.path.replaceAll('\\', '/');
  return entityPath == _allowedExternalAdapterPath;
}

void main() {
  group('PdvV1RemoteStockApply R2-B scope guard', () {
    late String modelsSource;
    late String orchestratorSource;
    late String rulesSource;
    late String r2RunnerSource;

    setUpAll(() {
      modelsSource = File(
        'lib/services/pdv_v1_internal/pdv_v1_remote_stock_apply_models.dart',
      ).readAsStringSync();
      orchestratorSource = File(
        'lib/services/pdv_v1_internal/pdv_v1_remote_stock_apply_orchestrator.dart',
      ).readAsStringSync();
      rulesSource = File('firestore.rules').readAsStringSync();
      r2RunnerSource = File(
        'test/pdv_v1_rules_v1/support/pdv_v1_atomic_stock_marker_runner.mjs',
      ).readAsStringSync();
    });

    test('1. R2-B não importa cloud_firestore', () {
      for (final src in [modelsSource, orchestratorSource]) {
        expect(src, isNot(contains('cloud_firestore')));
        expect(src, isNot(contains('FirebaseFirestore')));
        expect(src, isNot(contains('runTransaction')));
      }
    });

    test('2. R2-B não importa pdv_v1_infrastructure', () {
      for (final src in [modelsSource, orchestratorSource]) {
        expect(src, isNot(contains('pdv_v1_infrastructure')));
        expect(
            src, isNot(contains('PdvV1CloudFirestoreRemoteStockMarkerPort')));
      }
    });

    test(
        '3. R2-B não usa FirebaseAuth, Hive, SharedPreferences, UUID, DateTime.now, UI',
        () {
      for (final src in [modelsSource, orchestratorSource]) {
        expect(src, isNot(contains('FirebaseAuth')));
        expect(src, isNot(contains('Hive.openBox')));
        expect(src, isNot(contains('Hive.init')));
        expect(src, isNot(contains('SharedPreferences')));
        expect(src, isNot(contains('Uuid')));
        expect(src, isNot(contains('package:uuid')));
        expect(src, isNot(contains('DateTime.now')));
        expect(src, isNot(contains('BuildContext')));
        expect(src, isNot(contains('package:flutter/material')));
        expect(src, isNot(contains('package:flutter/widgets')));
      }
    });

    test(
        '4. executor obrigatório injetado sem porta transacional no orquestrador',
        () {
      expect(
        orchestratorSource,
        contains('required PdvV1RemoteStockMarkerExecutor executor'),
      );
      expect(orchestratorSource,
          isNot(contains('PdvV1RemoteStockMarkerExecutor?')));
      expect(orchestratorSource,
          isNot(contains('?? PdvV1RemoteStockMarkerExecutor')));
      expect(orchestratorSource,
          isNot(contains('PdvV1RemoteStockMarkerExecutor(')));
      expect(orchestratorSource,
          isNot(contains('PdvV1RemoteStockMarkerTransactionPort')));
    });

    test('5. nenhum call site produtivo referencia R2-B', () async {
      final tokens = [
        'PdvV1RemoteStockApplyOrchestrator',
        'pdv_v1_remote_stock_apply',
      ];
      final roots = [
        Directory('lib/screens'),
        Directory('lib/services'),
      ];
      final hits = <String>[];
      for (final root in roots) {
        if (!await root.exists()) continue;
        await for (final entity in root.list(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('pdv_v1_internal')) continue;
          if (isExactAllowedExternalAdapter(entity)) continue;
          final content = await entity.readAsString();
          for (final token in tokens) {
            if (content.contains(token)) hits.add('${entity.path}:$token');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });

    test('6. sem referência em telas/modal/vendas/sync/pagamentos', () async {
      final paths = [
        'lib/screens/nova_venda_modal.dart',
        'lib/services/vendas_service.dart',
        'lib/screens/order_review_screen.dart',
        'lib/screens/pedido_publico_screen.dart',
      ];
      final tokens = [
        'PdvV1RemoteStockApply',
        'pdv_v1_remote_stock_apply',
      ];
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        for (final token in tokens) {
          expect(content.contains(token), isFalse, reason: '$path:$token');
        }
      }
      for (final name in [
        'sync_queue_service.dart',
        'pagamentos_service.dart'
      ]) {
        final hits = await _grepFile(
            Directory('lib/services'), name, 'PdvV1RemoteStockApply');
        expect(hits, isEmpty);
      }
    });

    test('7. R2-A.2 exact allowlist presente no pipeline guard', () {
      final lines = File(
        'test/pdv_v1_internal/pdv_v1_pipeline_scope_guard_test.dart',
      ).readAsLinesSync();
      final callSiteStart = lines.indexWhere(
        (line) => line.contains(
          "test('nenhum call site de produção referencia pdv_v1_internal'",
        ),
      );
      final callSiteEnd = lines.indexWhere(
        (line) => line.contains("test('allowlist exata autoriza"),
      );
      expect(callSiteStart, greaterThanOrEqualTo(0));
      expect(callSiteEnd, greaterThan(callSiteStart));
      final callSiteBlock =
          lines.sublist(callSiteStart, callSiteEnd).join('\n');
      expect(callSiteBlock, contains('isExactAllowedExternalAdapter(entity)'));
    });

    test('8. R2-B não cria nova allowlist externa', () {
      for (final src in [modelsSource, orchestratorSource]) {
        expect(src, isNot(contains('isExactAllowedExternalAdapter')));
        expect(src, isNot(contains('pdv_v1_infrastructure')));
      }
    });

    test('9. firestore.rules contém bloco V1 R1 intacto', () {
      expect(rulesSource, contains('isV1MarkerCreate'));
      expect(rulesSource, contains('estoque_baixa_pagamento/{markerId}'));
    });

    test('10. runner R2 demo-only e local-only', () {
      expect(r2RunnerSource, contains('demo-masterpalm-pdv-v1-r2'));
      expect(r2RunnerSource, contains('isLocalEmulatorHost'));
      expect(r2RunnerSource, isNot(contains("from 'firebase-admin'")));
      expect(r2RunnerSource, isNot(contains('http://')));
      expect(r2RunnerSource, isNot(contains('emulators:start')));
      expect(r2RunnerSource, isNot(contains('firebase deploy')));
    });

    test('11. orquestrador sem loop, timer ou retry', () {
      for (final src in [modelsSource, orchestratorSource]) {
        expect(src, isNot(contains('while (')));
        expect(src, isNot(contains('Timer')));
        expect(src, isNot(contains('Future.delayed')));
        expect(src, isNot(contains('backoff')));
      }
    });

    test('12. construtor exige executor injetado sem default', () {
      final constructorBlock = RegExp(
        r'PdvV1RemoteStockApplyOrchestrator\s*\(\s*\{[^}]*required PdvV1RemoteStockMarkerExecutor executor',
        dotAll: true,
      );
      expect(constructorBlock.hasMatch(orchestratorSource), isTrue);
      expect(orchestratorSource,
          isNot(contains('PdvV1RemoteStockMarkerExecutor?')));
      expect(orchestratorSource,
          isNot(contains('?? PdvV1RemoteStockMarkerExecutor')));
      expect(orchestratorSource,
          isNot(contains('PdvV1RemoteStockMarkerExecutor(')));
    });
  });
}

Future<List<String>> _grepFile(
  Directory root,
  String fileName,
  String needle,
) async {
  final hits = <String>[];
  await for (final entity in root.list(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith(fileName)) continue;
    if (await entity.readAsString().then((s) => s.contains(needle))) {
      hits.add(entity.path);
    }
  }
  return hits;
}
