import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final canonicalSource = File(
    'lib/services/pdv_v1_internal/pdv_v1_canonical_json.dart',
  ).readAsStringSync();
  final preparationSource = File(
    'lib/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart',
  ).readAsStringSync();
  final rulesSource = File('firestore.rules').readAsStringSync();
  final r1RunnerSource = File(
    'test/pdv_v1_rules_v1/support/pdv_v1_atomic_stock_marker_runner.mjs',
  ).readAsStringSync();
  final adapterSource = File(
    'lib/services/pdv_v1_infrastructure/'
    'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
  ).readAsStringSync();

  const phaseLibFiles = [
    'lib/services/pdv_v1_internal/pdv_v1_canonical_json.dart',
    'lib/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart',
  ];

  group('R2-C.2 simple sale preparation scope guard', () {
    test('1. somente dois arquivos lib novos desta fase', () {
      for (final path in phaseLibFiles) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('2. nenhum import proibido nos arquivos novos', () {
      final forbidden = [
        'cloud_firestore',
        'FirebaseFirestore',
        'FirebaseAuth',
        'package:hive',
        'Hive.',
        'SharedPreferences',
        'package:uuid',
        'Uuid(',
        'DateTime.now',
        'BuildContext',
        'package:flutter/material',
        'package:flutter/widgets',
        'pdv_v1_infrastructure',
        'pdv_v1_hive_journal_repository',
        'pdv_v1_remote_stock_marker_executor',
      ];
      for (final src in [canonicalSource, preparationSource]) {
        for (final token in forbidden) {
          expect(src.contains(token), isFalse, reason: token);
        }
      }
    });

    test('3. preparador não referencia journal, pending ou executor remoto',
        () {
      final forbidden = [
        'PdvV1JournalRecord',
        'PdvV1HiveJournalRepository',
        'remoteStockPending',
        'persistIfRevisionMatches',
        'applyOnce',
        'runTransaction',
        'PdvV1RemoteStockApplyOrchestrator',
      ];
      for (final token in forbidden) {
        expect(preparationSource.contains(token), isFalse, reason: token);
        expect(canonicalSource.contains(token), isFalse, reason: token);
      }
    });

    test('4. preparador sem timer, loop, retry, hashCode, jsonEncode map/list',
        () {
      for (final src in [canonicalSource, preparationSource]) {
        expect(src, isNot(contains('while (')));
        expect(src, isNot(contains('Timer')));
        expect(src, isNot(contains('Future.delayed')));
        expect(src, isNot(contains('retry')));
        expect(src, isNot(contains('backoff')));
        expect(src, isNot(contains('hashCode')));
        expect(src, isNot(contains('Map.from')));
        expect(src, isNot(contains('...')));
      }
      expect(preparationSource, isNot(contains('jsonEncode(')));
      expect(
        canonicalSource.contains('jsonEncode('),
        isTrue,
        reason: 'jsonEncode permitido apenas para escaping de String',
      );
    });

    test('5. preparador usa crypto SHA-256 UTF-8 hex minúsculo', () {
      expect(canonicalSource, contains("import 'package:crypto/crypto.dart'"));
      expect(canonicalSource, contains('sha256.convert'));
      expect(canonicalSource, contains('utf8.encode'));
      expect(preparationSource, contains('pdv_v1_canonical_json.dart'));
      expect(preparationSource, contains('pdvV1CanonicalSha256'));
    });

    test('6. sem call site produtivo para tipos novos', () async {
      final paths = [
        'lib/screens/nova_venda_modal.dart',
        'lib/services/vendas_service.dart',
        'lib/services/estoque_transaction_service.dart',
        'lib/screens/order_review_screen.dart',
        'lib/screens/pedido_publico_screen.dart',
      ];
      final tokens = [
        'PdvV1SimpleSalePreparation',
        'pdv_v1_simple_sale_preparation',
        'pdvV1Canonical',
        'pdv_v1_canonical_json',
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
        'pagamentos_service.dart',
        'venda_combo_estoque_expansion.dart',
      ]) {
        final hits = await _grepFile(
          Directory('lib/services'),
          name,
          'pdv_v1_simple_sale_preparation',
        );
        expect(hits, isEmpty);
      }
    });

    test('7. Rules, adapter R2-A e runners sem referência aos tipos novos', () {
      for (final src in [rulesSource, adapterSource, r1RunnerSource]) {
        expect(src.contains('pdv_v1_simple_sale_preparation'), isFalse);
        expect(src.contains('pdv_v1_canonical_json'), isFalse);
        expect(src.contains('PdvV1SimpleSalePreparation'), isFalse);
      }
      expect(rulesSource, contains('isV1MarkerCreate'));
      expect(r1RunnerSource, contains('estoque_baixa_pagamento'));
      expect(r1RunnerSource, contains('demo-masterpalm-pdv-v1-r2'));
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
