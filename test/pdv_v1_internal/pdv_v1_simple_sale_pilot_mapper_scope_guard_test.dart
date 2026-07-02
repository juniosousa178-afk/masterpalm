import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final mapperSource = File(
    'lib/services/pdv_v1_internal/pdv_v1_simple_sale_pilot_mapper.dart',
  ).readAsStringSync();
  final rulesSource = File('firestore.rules').readAsStringSync();
  final r1RunnerSource = File(
    'test/pdv_v1_rules_v1/support/pdv_v1_atomic_stock_marker_runner.mjs',
  ).readAsStringSync();
  final adapterSource = File(
    'lib/services/pdv_v1_infrastructure/'
    'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
  ).readAsStringSync();

  group('R2-C.5.1 simple sale pilot mapper scope guard', () {
    test('1. mapper importa somente dependências permitidas', () {
      expect(mapperSource, contains("import '../../models/produto.dart'"));
      expect(mapperSource, contains("import '../../models/venda_item.dart'"));
      expect(mapperSource, contains("import 'pdv_v1_internal_models.dart'"));
      expect(
        mapperSource,
        contains("import 'pdv_v1_simple_sale_preparation.dart'"),
      );
    });

    test('2. mapper não importa nem referencia dependências proibidas', () {
      final forbidden = [
        'cloud_firestore',
        'FirebaseFirestore',
        'FirebaseAuth',
        'package:hive',
        'Hive.',
        'Box<',
        'SharedPreferences',
        'package:uuid',
        'Uuid(',
        'DateTime.now',
        'Clock',
        'BuildContext',
        'Widget',
        'package:flutter/material',
        'package:flutter/widgets',
        'pdv_v1_infrastructure',
        'PdvV1PreparedJournalWriter',
        'PdvV1InitialPreparedJournalCreateRepository',
        'PdvV1JournalRepository',
        'PdvV1HiveJournalRepository',
        'PdvV1JournalRecord',
        'remoteStockPending',
        'PdvV1RemoteStockApplyOrchestrator',
        'PdvV1RemoteStockMarkerExecutor',
        'applyOnce',
        'createInitialPreparedIfAbsent',
        'readByOperationId',
        'persistIfRevisionMatches',
        'baixarEstoqueTransactionBatch',
        'registrarVendaMulti',
        'Timer',
        'Future.delayed',
        'retry',
        'backoff',
        'hashCode',
        'Map.from',
        'Map<String, dynamic>.from',
      ];
      for (final token in forbidden) {
        expect(mapperSource.contains(token), isFalse, reason: token);
      }
    });

    test('3. mapper usa enum fechado de origem', () {
      expect(mapperSource, contains('enum PdvV1SimpleSalePilotOrigin'));
      expect(mapperSource, contains('novaVendaModal'));
      expect(mapperSource, isNot(contains('String origin')));
    });

    test('4. stockDocumentId deriva de resolvedProduct.idFirebase', () {
      expect(mapperSource, contains('context.resolvedProduct.idFirebase'));
      expect(mapperSource, isNot(contains('item.productId')));
      expect(mapperSource, isNot(contains('.slug')));
      expect(mapperSource, isNot(contains('.sku')));
      expect(mapperSource, isNot(contains('.nome')));
    });

    test('5. helper stock shape rejeita estoquePorTamanho não vazio', () {
      expect(mapperSource, contains('product.estoquePorTamanho.isNotEmpty'));
    });

    test('6. nenhum call site produtivo referencia o mapper', () {
      final libDir = Directory('lib');
      final servicesDir = Directory('lib/services');
      final screensDir = Directory('lib/screens');

      for (final dir in [libDir, servicesDir, screensDir]) {
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path
              .replaceAll('\\', '/')
              .endsWith('pdv_v1_simple_sale_pilot_mapper.dart')) {
            continue;
          }
          final src = entity.readAsStringSync();
          expect(
            src.contains('PdvV1SimpleSalePilotContext'),
            isFalse,
            reason: entity.path,
          );
          expect(
            src.contains('pdvV1MapSimpleSalePilot'),
            isFalse,
            reason: entity.path,
          );
          expect(
            src.contains('pdvV1IsKnownSimpleDirectStock'),
            isFalse,
            reason: entity.path,
          );
        }
      }
    });

    test('7. rules, adapter e runner não referenciam o mapper', () {
      for (final src in [rulesSource, r1RunnerSource, adapterSource]) {
        expect(src.contains('pdv_v1_simple_sale_pilot_mapper'), isFalse);
        expect(src.contains('pdvV1MapSimpleSalePilot'), isFalse);
        expect(src.contains('PdvV1SimpleSalePilotContext'), isFalse);
      }
    });
  });
}
