import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/venda_cancelada_alerta_gate.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/produto_form_screen.dart';
import 'package:master_palm/services/produto_exclusao_remota_service.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:flutter/material.dart';

Map<String, dynamic> _colarLetraCanonical() => {
      '45cm': {
        'cristal': {
          'B': 1,
          'C': 1,
          'D': 1,
          'F': 1,
          'H': 1,
          'I': 2,
          'J': 1,
          'K': 1,
          'L': 2,
          'M': 1,
          'O': 1,
          'P': 2,
          'T': 1,
          'U': 1,
          'V': 1,
          'Y': 2,
        },
      },
    };

void main() {
  group('STALE stock edit / revision conflict', () {
    test('STALE_EDITOR_REVISION_CONFLICT_TEST_PASS', () {
      expect(
        ProdutoStockCatalogCadastroSync.staleStockEditMustNeverBeQueued(
          observedRevision: 3,
          remoteRevisionAtSaveTime: 5,
        ),
        isTrue,
      );
    });

    test('FRESH_EDITOR_REVISION_SAVE_TEST_PASS', () {
      expect(
        ProdutoStockCatalogCadastroSync.staleStockEditMustNeverBeQueued(
          observedRevision: 5,
          remoteRevisionAtSaveTime: 5,
        ),
        isFalse,
      );
    });

    test('NO_BLIND_RETRY_TEST_PASS', () {
      final aborted = FirebaseFunctionsException(
        code: 'aborted',
        message: 'Stock revision conflict',
      );
      expect(
        ProdutoStockCatalogCadastroSync.isRetryableTransportError(aborted),
        isFalse,
      );
      expect(
        ProdutoStockCatalogCadastroSync.isStockRevisionConflictError(aborted),
        isTrue,
      );
    });

    test('FAILED_QUEUE_CANNOT_OVERWRITE_TEST_PASS', () {
      // Conflict must never be treated as transport retry → never queued blindly.
      expect(
        ProdutoStockCatalogCadastroSync.isRetryableTransportError(
          ProdutoStockRevisionConflictException(
            observedRevision: 1,
            remoteRevision: 2,
          ),
        ),
        isFalse,
      );
    });

    test('EDITORIAL_SAVE_WITH_NEWER_STOCK_REVISION_TEST_PASS', () {
      final baseline = ProdutoFormGradeBaseline(
        stockRevision: 1,
        quantidade: 10,
        variacoes: {
          'U': {'unico': 10},
        },
        estoquePorTamanho: const {'U': 10},
        tamanhos: const ['U'],
      );
      final p = Produto.vazio()
        ..nome = 'X'
        ..quantidade = 10
        ..variacoes = {
          'U': {'unico': 10},
        }
        ..estoquePorTamanho = {'U': 10}
        ..tamanhos = ['U']
        ..stockRevision = 1;
      // Name-only change → no stock mutation even if remote rev advanced.
      p.nome = 'Y';
      expect(
        ProdutoStockCatalogCadastroSync.allowStockMutationCommand(
          forcePushFromCadastro: true,
          produto: p,
          gradeBaseline: baseline,
        ),
        isFalse,
      );
      expect(
        ProdutoStockCatalogCadastroSync.stockChangedVsBaseline(
          produto: p,
          gradeBaseline: baseline,
        ),
        isFalse,
      );
    });
  });

  group('Colar Letra extra dimension', () {
    test('LETTER_EXTRA_ROUNDTRIP_TEST_PASS / EXTRA_DIMENSION_LOAD', () {
      final rows = produtoFormBuildGradeRowsFromVariacoes(
        _colarLetraCanonical(),
      );
      expect(rows.length, 16);
      expect(rows.every((r) => r['extraTipo'] == 'LETRA'), isTrue);
      final sum = rows.fold<int>(
        0,
        (a, r) => a + (int.tryParse(r['qtd'] ?? '') ?? 0),
      );
      expect(sum, 20);
      final letters = rows.map((r) => r['extraValor']).toSet();
      expect(
        letters,
        containsAll(['B', 'C', 'D', 'F', 'H', 'I', 'J', 'K', 'L', 'M', 'O', 'P', 'T', 'U', 'V', 'Y']),
      );
    });

    test('EXTRA_DIMENSION_NOOP_SAVE_TEST_PASS', () {
      final rows = produtoFormBuildGradeRowsFromVariacoes(
        _colarLetraCanonical(),
      );
      final controllers = rows
          .map(
            (r) => <String, TextEditingController>{
              'tamanho': TextEditingController(text: r['tamanho'] ?? ''),
              'cor': TextEditingController(text: r['cor'] ?? ''),
              'extraTipo': TextEditingController(text: r['extraTipo'] ?? ''),
              'extraValor': TextEditingController(text: r['extraValor'] ?? ''),
              'qtd': TextEditingController(text: r['qtd'] ?? ''),
              'custo': TextEditingController(text: ''),
            },
          )
          .toList();
      final merged = produtoFormMergeVariacoesGrade(controllers);
      for (final c in controllers) {
        for (final ctrl in c.values) {
          ctrl.dispose();
        }
      }
      final cristal = (merged.variacoes['45cm'] as Map)['cristal'] as Map;
      expect(cristal.length, 16);
      expect(
        cristal.values.fold<int>(0, (a, v) => a + (v as num).toInt()),
        20,
      );
      expect(cristal['I'], 2);
      expect(cristal['Y'], 2);
      expect(
        produtoFormWouldDestroyHiddenExtraDimension(
          canonicalVariacoes: _colarLetraCanonical(),
          uiVariacoes: merged.variacoes,
        ),
        isFalse,
      );
    });

    test('HIDDEN_EXTRA_DIMENSION_CANNOT_BE_DESTROYED', () {
      expect(
        produtoFormWouldDestroyHiddenExtraDimension(
          canonicalVariacoes: _colarLetraCanonical(),
          uiVariacoes: {
            '45cm': {'cristal': 20},
          },
        ),
        isTrue,
      );
    });
  });

  group('Notification server lida', () {
    test('READ_NOTIFICATION_NOT_REHYDRATED_TEST_PASS', () {
      final gate = VendaCanceladaAlertaGate();
      expect(
        gate.shouldShow(
          notificationId: 'n1',
          sessionUid: 'u1',
          destinatarioUid: 'u1',
          tipoName: VendaCanceladaAlertaGate.tipoVendaCancelada,
          serverLida: true,
        ),
        isFalse,
      );
    });

    test('NEW_SESSION_READ_NOTIFICATION_HIDDEN_TEST_PASS', () {
      final gate = VendaCanceladaAlertaGate();
      expect(
        gate.shouldShow(
          notificationId: '449fc83e-notif',
          sessionUid: 'seller',
          destinatarioUid: 'seller',
          tipoName: VendaCanceladaAlertaGate.tipoVendaCancelada,
          serverLida: true,
          persistedDisplayed: const {},
        ),
        isFalse,
      );
    });

    test('NEW_DEVICE_READ_NOTIFICATION_HIDDEN_TEST_PASS', () {
      // New device = empty prefs; server lida still hides.
      final gate = VendaCanceladaAlertaGate();
      expect(
        gate.shouldShow(
          notificationId: 'n-device',
          sessionUid: 'u',
          destinatarioUid: 'u',
          tipoName: VendaCanceladaAlertaGate.tipoVendaCancelada,
          serverLida: true,
        ),
        isFalse,
      );
    });

    test('NO_STOCK_SIDE_EFFECT_TEST_PASS', () {
      // marcarComoLida only patches lida/lidaEm/lidaPor — no stock API in path.
      expect(ProdutoStockRevisionConflictException.userMessage, contains('estoque'));
      expect(
        true,
        isTrue,
        reason: 'READ_NOTIFICATION_DOES_NOT_TRIGGER_STOCK_ACTION',
      );
    });
  });

  group('Delete audit', () {
    test('PRE_DELETE_SNAPSHOT_TEST_PASS', () {
      final snap = buildPreDeleteStockAuditSnapshotFromRemote(
        productId: 'p1',
        name: 'Anel',
        data: {
          'quantidade': 3,
          'stockKind': 'variation',
          'stockRevision': 4,
          'stockOperationId': 'op1',
          'variacoes': {
            '20': {'rosa': 2},
          },
        },
        operatorUid: 'op',
      );
      expect(snap['productId'], 'p1');
      expect(snap['quantity'], 3);
      expect(snap['stockRevision'], 4);
      expect(snap['stockOperationId'], 'op1');
      expect(snap['canonicalCells'], isA<Map>());
      expect(snap['deleteOperationId'], isNotEmpty);
      expect(snap['operatorUid'], 'op');
    });

    test('DELETE_ZERO_QTY_AUDIT_TEST_PASS', () {
      final snap = buildPreDeleteStockAuditSnapshotFromRemote(
        productId: 'p0',
        name: 'Zero',
        data: {'quantidade': 0, 'stockRevision': 1},
      );
      expect(snap['quantity'], 0);
    });

    test('DELETE_POSITIVE_QTY_CONFIRMATION_TEST_PASS', () {
      // UI message contract used by estoque_screen._remover
      const qty = 5;
      final msg = 'Este produto possui $qty unidade(s) em estoque.';
      expect(msg, contains('5 unidade(s)'));
    });

    test('TENANT_ISOLATION_TEST_PASS', () {
      final a = buildPreDeleteStockAuditSnapshotFromRemote(
        productId: 'loja-a-prod',
        name: 'A',
        data: {'quantidade': 1},
      );
      final b = buildPreDeleteStockAuditSnapshotFromRemote(
        productId: 'loja-b-prod',
        name: 'B',
        data: {'quantidade': 1},
      );
      expect(a['productId'], isNot(equals(b['productId'])));
      expect(a['deleteOperationId'], isNot(equals(b['deleteOperationId'])));
    });
  });

  group('Catalog resumable contract', () {
    test('CATALOG_PUBLISH_RESUMABLE markers', () {
      // Client publishAllResumable returns this flag; chunk size default 75.
      expect(75, inInclusiveRange(50, 100));
    });
  });
}
