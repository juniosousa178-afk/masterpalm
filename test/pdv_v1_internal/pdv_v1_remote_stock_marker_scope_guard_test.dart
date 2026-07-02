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
  group('PdvV1RemoteStockMarker R2-A scope guard', () {
    late String executorSource;
    late String cloudPortSource;
    late String modelsSource;
    late String portSource;
    late String rulesSource;
    late String r2RunnerSource;

    setUpAll(() {
      const internalBase = 'lib/services/pdv_v1_internal';
      const infraBase = 'lib/services/pdv_v1_infrastructure';
      executorSource =
          File('$internalBase/pdv_v1_remote_stock_marker_executor.dart')
              .readAsStringSync();
      cloudPortSource = File(
        '$infraBase/pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
      ).readAsStringSync();
      modelsSource =
          File('$internalBase/pdv_v1_remote_stock_marker_models.dart')
              .readAsStringSync();
      portSource = File(
        '$internalBase/pdv_v1_remote_stock_marker_transaction_port.dart',
      ).readAsStringSync();
      rulesSource = File('firestore.rules').readAsStringSync();
      r2RunnerSource = File(
        'test/pdv_v1_rules_v1/support/pdv_v1_atomic_stock_marker_runner.mjs',
      ).readAsStringSync();
    });

    test('1. executor não importa cloud_firestore', () {
      expect(executorSource, isNot(contains('cloud_firestore')));
    });

    test('2. apenas adapter externo importa cloud_firestore', () {
      expect(modelsSource, isNot(contains('cloud_firestore')));
      expect(portSource, isNot(contains('cloud_firestore')));
      expect(executorSource, isNot(contains('cloud_firestore')));
      expect(cloudPortSource, contains('cloud_firestore'));
      final internalDir = Directory('lib/services/pdv_v1_internal');
      for (final entity in internalDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        expect(
          entity.readAsStringSync().contains('cloud_firestore'),
          isFalse,
          reason: '${entity.path} não deve importar cloud_firestore',
        );
      }
    });

    test(
        '2b. nenhum segundo arquivo em pdv_v1_infrastructure importa pdv_v1_internal',
        () {
      final infraDir = Directory('lib/services/pdv_v1_infrastructure');
      if (!infraDir.existsSync()) {
        fail('pdv_v1_infrastructure ausente');
      }
      final violations = <String>[];
      for (final entity in infraDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (isExactAllowedExternalAdapter(entity)) continue;
        final content = entity.readAsStringSync();
        if (content.contains('pdv_v1_internal')) {
          violations.add(entity.path);
        }
      }
      expect(violations, isEmpty, reason: violations.join(', '));
    });

    test('3. não existe FirebaseFirestore.instance', () {
      for (final src in [
        executorSource,
        cloudPortSource,
        modelsSource,
        portSource
      ]) {
        expect(src, isNot(contains('FirebaseFirestore.instance')));
      }
    });

    test('4. não existe FirebaseAuth', () {
      for (final src in [
        executorSource,
        cloudPortSource,
        modelsSource,
        portSource
      ]) {
        expect(src, isNot(contains('FirebaseAuth')));
      }
    });

    test('5. não existe Hive.openBox/init/close', () {
      for (final src in [
        executorSource,
        cloudPortSource,
        modelsSource,
        portSource
      ]) {
        expect(src, isNot(contains('Hive.openBox')));
        expect(src, isNot(contains('Hive.init')));
        expect(src, isNot(contains('.close(')));
      }
    });

    test('6. não existe SharedPreferences', () {
      for (final src in [
        executorSource,
        cloudPortSource,
        modelsSource,
        portSource
      ]) {
        expect(src, isNot(contains('SharedPreferences')));
      }
    });

    test('7. não existe DateTime.now', () {
      for (final src in [
        executorSource,
        cloudPortSource,
        modelsSource,
        portSource
      ]) {
        expect(src, isNot(contains('DateTime.now')));
      }
    });

    test('8. não existe UUID', () {
      for (final src in [
        executorSource,
        cloudPortSource,
        modelsSource,
        portSource
      ]) {
        expect(src, isNot(contains('Uuid')));
        expect(src, isNot(contains('package:uuid')));
      }
    });

    test('9. nenhum call site de produção referencia tipos R2-A', () async {
      final tokens = [
        'PdvV1RemoteStockMarkerExecutor',
        'PdvV1RemoteStockMarkerPlan',
        'PdvV1CloudFirestoreRemoteStockMarkerPort',
        'pdv_v1_remote_stock_marker',
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

    test('10. sem referência em telas/modal/vendas/sync/pagamentos', () async {
      final paths = [
        'lib/screens/nova_venda_modal.dart',
        'lib/services/vendas_service.dart',
        'lib/screens/order_review_screen.dart',
        'lib/screens/pedido_publico_screen.dart',
      ];
      final tokens = [
        'PdvV1RemoteStockMarker',
        'pdv_v1_remote_stock_marker',
      ];
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        for (final token in tokens) {
          expect(content.contains(token), isFalse, reason: '$path:$token');
        }
      }
      for (final name in ['sync_queue_service.dart']) {
        final hits = await _grepFile(
            Directory('lib/services'), name, 'PdvV1RemoteStockMarker');
        expect(hits, isEmpty);
      }
    });

    test('11. firestore.rules contém bloco V1 R1 intacto', () {
      expect(rulesSource, contains('isV1MarkerCreate'));
      expect(rulesSource, contains('estoque_baixa_pagamento/{markerId}'));
    });

    test('12. runner R2 usa demo-masterpalm-pdv-v1-r2 e host local', () {
      expect(r2RunnerSource, contains('demo-masterpalm-pdv-v1-r2'));
      expect(r2RunnerSource, contains('isLocalEmulatorHost'));
    });

    test('13. runner R2 não usa firebase-admin operacional', () {
      expect(r2RunnerSource, isNot(contains("from 'firebase-admin'")));
      expect(r2RunnerSource, isNot(contains('from "firebase-admin"')));
    });

    test('14. runner R2 não usa URL externa', () {
      expect(r2RunnerSource, isNot(contains('http://')));
      expect(r2RunnerSource, isNot(contains('https://')));
    });

    test('15. runner R2 não inicia emulator', () {
      expect(r2RunnerSource, isNot(contains('emulators:start')));
    });

    test('16. runner R2 não faz deploy', () {
      expect(r2RunnerSource, isNot(contains('firebase deploy')));
    });

    test('17. allowlist exata autoriza somente o adapter Cloud Firestore R2-A',
        () {
      expect(
        isExactAllowedExternalAdapter(
          File(
            'lib/services/pdv_v1_infrastructure/'
            'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
          ),
        ),
        isTrue,
      );
      expect(
        isExactAllowedExternalAdapter(
          File(
            'lib/services/pdv_v1_infrastructure/'
            'pdv_v1_cloud_firestore_remote_stock_marker_port_2.dart',
          ),
        ),
        isFalse,
      );
      expect(
        isExactAllowedExternalAdapter(
          File('lib/services/pdv_v1_infrastructure/outro_adapter.dart'),
        ),
        isFalse,
      );
      expect(
        isExactAllowedExternalAdapter(
          File(
            'lib/services/pdv_v1_infrastructure/subdir/'
            'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
          ),
        ),
        isFalse,
      );
      expect(
        isExactAllowedExternalAdapter(
          File(
            'lib/services/pdv_v1_other/'
            'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
          ),
        ),
        isFalse,
      );
    });

    test('18. allowlist não usa exclusão ampla de pdv_v1_infrastructure', () {
      final lines = File(
        'test/pdv_v1_internal/pdv_v1_remote_stock_marker_scope_guard_test.dart',
      ).readAsLinesSync();
      final callSiteStart = lines.indexWhere(
        (line) => line.contains(
          "test('9. nenhum call site de produção referencia tipos R2-A'",
        ),
      );
      final callSiteEnd = lines.indexWhere(
        (line) => line.contains("test('10. sem referência em telas"),
      );
      expect(callSiteStart, greaterThanOrEqualTo(0));
      expect(callSiteEnd, greaterThan(callSiteStart));
      final callSiteBlock =
          lines.sublist(callSiteStart, callSiteEnd).join('\n');
      expect(
          callSiteBlock, isNot(contains("contains('pdv_v1_infrastructure')")));
      expect(
          callSiteBlock, isNot(contains('contains("pdv_v1_infrastructure")')));
      expect(callSiteBlock, contains('isExactAllowedExternalAdapter(entity)'));
    });

    test('19. núcleo interno não referencia pdv_v1_infrastructure', () {
      final internalDir = Directory('lib/services/pdv_v1_internal');
      final hits = <String>[];
      for (final entity in internalDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('pdv_v1_infrastructure')) {
          hits.add(entity.path);
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
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
