import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_errors.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_pipeline_foundation.dart';

final _allowedExternalAdapterPath = File(
  'lib/services/pdv_v1_infrastructure/'
  'pdv_v1_cloud_firestore_remote_stock_marker_port.dart',
).absolute.path.replaceAll('\\', '/');

bool isExactAllowedExternalAdapter(File entity) {
  final entityPath = entity.absolute.path.replaceAll('\\', '/');
  return entityPath == _allowedExternalAdapterPath;
}

PdvV1PreparedSnapshot _snap({
  PdvV1InternalOrigin origem = PdvV1InternalOrigin.novaVendaPdvFuture,
  bool isFiado = false,
  bool hasCombo = false,
  bool isEdicao = false,
  bool isCancelamento = false,
}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-pipe-1',
    saleId: 'sale-pipe-1',
    lojaId: 'loja-pipe-1',
    origem: origem,
    preparedAtEpochMs: 1,
    preparedSnapshot: const {'a': 1},
    snapshotHash: 'snap-pipe',
    txItemsHash: 'tx-pipe',
    isFiado: isFiado,
    hasCombo: hasCombo,
    isEdicao: isEdicao,
    isCancelamento: isCancelamento,
  );
}

void main() {
  final pipeline = PdvV1PipelineFoundation();

  group('PdvV1PipelineFoundation scope guard', () {
    test('bloqueia origens legadas', () {
      for (final origem in PdvV1InternalOrigin.values) {
        if (origem == PdvV1InternalOrigin.novaVendaPdvFuture) continue;
        expect(
          () => pipeline.validateScope(_snap(origem: origem)),
          throwsA(isA<PdvV1ScopeNotSupportedError>()),
        );
      }
    });

    test('bloqueia fiado, combo, edição e cancelamento', () {
      expect(
        () => pipeline.validateScope(_snap(isFiado: true)),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
      expect(
        () => pipeline.validateScope(_snap(hasCombo: true)),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
      expect(
        () => pipeline.validateScope(_snap(isEdicao: true)),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
      expect(
        () => pipeline.validateScope(_snap(isCancelamento: true)),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
    });

    test('nunca executa integração externa', () {
      expect(
        () => pipeline.assertNotIntegratedExecution(),
        throwsA(isA<PdvV1ExecutionNotIntegratedError>()),
      );
    });

    test('preValidate retorna resultado serializável', () {
      final result = pipeline.preValidate(
        prepared: _snap(),
        txItems: const [
          PdvV1TxItemFrozen(productId: 'p1', quantidade: 1),
        ],
        transitionFrom: PdvV1JournalState.prepared,
        transitionTo: PdvV1JournalState.remoteStockPending,
      );
      expect(result.scopeValid, isTrue);
      expect(result.snapshotValid, isTrue);
      expect(result.transitionValid, isTrue);
      expect(result.toJson()['scopeValid'], isTrue);
    });

    test('nenhum arquivo novo importa Firebase ou Widgets', () async {
      final dir = Directory('lib/services/pdv_v1_internal');
      final forbidden = [
        'FirebaseFirestore',
        'FirebaseAuth',
        'runTransaction',
        'Hive.openBox',
        'SharedPreferences',
        'package:flutter/material',
        'package:flutter/widgets',
      ];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
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

    test('nenhum call site de produção referencia pdv_v1_internal', () async {
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
          if (content.contains('pdv_v1_internal')) {
            hits.add(entity.path);
          }
        }
      }
      expect(hits, isEmpty, reason: 'call sites: $hits');
    });

    test('allowlist exata autoriza somente o adapter Cloud Firestore R2-A', () {
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

    test('allowlist não usa exclusão ampla de pdv_v1_infrastructure', () {
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
      expect(
          callSiteBlock, isNot(contains("contains('pdv_v1_infrastructure')")));
      expect(
          callSiteBlock, isNot(contains('contains("pdv_v1_infrastructure")')));
      expect(callSiteBlock, contains('isExactAllowedExternalAdapter(entity)'));
    });
  });
}
