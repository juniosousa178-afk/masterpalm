import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final writerSource = File(
    'lib/services/pdv_v1_internal/pdv_v1_prepared_journal_writer.dart',
  ).readAsStringSync();
  final rulesSource = File('firestore.rules').readAsStringSync();
  final r1RunnerSource = File(
    'test/pdv_v1_rules_v1/support/pdv_v1_atomic_stock_marker_runner.mjs',
  ).readAsStringSync();
  final adapterSource = File(
    'lib/services/pdv_v1_infrastructure/'
    'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
  ).readAsStringSync();

  group('R2-C.4.2 prepared journal writer scope guard', () {
    test(
        '1. writer depende somente de PdvV1InitialPreparedJournalCreateRepository',
        () {
      expect(
        writerSource,
        contains('pdv_v1_initial_prepared_journal_create_repository.dart'),
      );
      expect(
        writerSource,
        contains('PdvV1InitialPreparedJournalCreateRepository'),
      );
      expect(writerSource, contains('pdv_v1_simple_sale_preparation.dart'));
      expect(writerSource, isNot(contains('pdv_v1_journal_repository.dart')));
    });

    test('2. writer não contém dependências proibidas', () {
      final forbidden = [
        'PdvV1JournalRepository',
        'PdvV1HiveJournalRepository',
        'readByOperationId',
        '.put(',
        'Box<',
        'package:hive',
        'Hive.',
        'cloud_firestore',
        'FirebaseFirestore',
        'FirebaseAuth',
        'SharedPreferences',
        'package:uuid',
        'Uuid(',
        'DateTime.now',
        'BuildContext',
        'Widget',
        'package:flutter/material',
        'package:flutter/widgets',
        'pdv_v1_infrastructure',
        'remoteStockPending',
        'transition(',
        'persistIfRevisionMatches',
        'applyOnce',
        'pdv_v1_remote_stock_marker_executor',
        'PdvV1RemoteStockApplyOrchestrator',
        'Timer',
        'Future.delayed',
        'retry',
        'backoff',
        'package:meta/meta.dart',
        '@visibleForTesting',
      ];
      for (final token in forbidden) {
        expect(writerSource.contains(token), isFalse, reason: token);
      }
    });

    test(
        '3. writer chama createInitialPreparedIfAbsent uma única vez no fluxo elegível',
        () {
      expect(writerSource, contains('createInitialPreparedIfAbsent'));
      expect(
        'createInitialPreparedIfAbsent'.allMatches(writerSource).length,
        1,
      );
    });

    test(
        '4. writer não referencia PdvV1JournalRepository em assinatura ou campo',
        () {
      expect(writerSource, isNot(contains('PdvV1JournalRepository')));
      expect(
        writerSource,
        contains('initialPreparedJournalCreateRepository'),
      );
    });

    test('5. sem call site produtivo para writer ou capability', () async {
      final paths = [
        'lib/screens/nova_venda_modal.dart',
        'lib/services/vendas_service.dart',
        'lib/services/estoque_transaction_service.dart',
        'lib/screens/order_review_screen.dart',
        'lib/screens/pedido_publico_screen.dart',
      ];
      final tokens = [
        'PdvV1PreparedJournalWriter',
        'pdv_v1_prepared_journal_writer',
        'PdvV1InitialPreparedJournalCreateRepository',
        'createInitialPreparedIfAbsent',
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
          'PdvV1PreparedJournalWriter',
        );
        expect(hits, isEmpty);
      }
    });

    test(
        '6. Rules, adapter, runners e harness sem referência ao writer ou capability',
        () {
      for (final src in [rulesSource, adapterSource, r1RunnerSource]) {
        expect(src.contains('pdv_v1_prepared_journal_writer'), isFalse);
        expect(src.contains('PdvV1PreparedJournalWriter'), isFalse);
        expect(src.contains('PdvV1InitialPreparedJournalCreateRepository'),
            isFalse);
        expect(src.contains('createInitialPreparedIfAbsent'), isFalse);
      }
      expect(rulesSource, contains('isV1MarkerCreate'));
      expect(r1RunnerSource, contains('estoque_baixa_pagamento'));
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
