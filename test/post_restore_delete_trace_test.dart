import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/delete_forensic_trace.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:master_palm/models/produto.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/hive_test_helpers.dart';

/// Trace-only paths: no stock semantic changes asserted beyond stage sequence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late String hivePath;

  setUp(() async {
    DeleteForensicTraceStore.disableHive = true;
    DeleteForensicTraceStore.clearAll();
    StockCatalogBackendService.debugTransport = null;
    EstoqueTransactionService.debugClearOverrides();
    registerHiveAdaptersForTests();
    hivePath = await initHiveForTests();
  });

  tearDown(() async {
    DeleteForensicTraceStore.clearAll();
    StockCatalogBackendService.debugTransport = null;
    EstoqueTransactionService.debugClearOverrides();
    await Hive.close();
  });

  Future<Box<Produto>> seedProduto() async {
    final box = await Hive.openBox<Produto>('produtos_trace');
    final p = Produto(
      nome: 'Anel Lacinho Encanto',
      custoReal: 15,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 52.9,
      quantidade: 1,
      precoUnitario: 52.9,
      categoria: 'Anel',
      dataEntrada: DateTime(2026, 1, 1),
      lojaId: 'nathy-pratas-e-folheados',
      idFirebase: 'nathy-pratas-e-folheados-anel-lacinho-encanto',
      slug: 'nathy-pratas-e-folheados-anel-lacinho-encanto',
      stockRevision: 9,
      confirmedStockOperationId: '449fc83e-9a5e-4544-9bee-93348123a2dd',
      variacoes: {
        '15': {'sem-cor': 0},
        '22': {'sem-cor': 1},
      },
      estoquePorTamanho: const {'15': 0, '22': 1},
    );
    await box.add(p);
    return box;
  }

  Map<String, dynamic> restoreOk({required bool alreadyApplied}) => {
        'alreadyApplied': alreadyApplied,
        'operationId':
            'restore_cf365f7edea904d5c41b0768ffdcc75b7ba022ec397276f7ad38b564b00658d4',
        'products': [
          {
            'productId': 'nathy-pratas-e-folheados-anel-lacinho-encanto',
            'quantidade': 2,
            'stockRevision': 10,
            'stockOperationId':
                'restore_cf365f7edea904d5c41b0768ffdcc75b7ba022ec397276f7ad38b564b00658d4',
            'stockKind': 'variation',
            'nome': 'Anel Lacinho Encanto',
            'slug': 'nathy-pratas-e-folheados-anel-lacinho-encanto',
            'variacoes': {
              '15': {'sem-cor': 1},
              '22': {'sem-cor': 1},
            },
            'estoquePorTamanho': {'15': 1, '22': 1},
          },
        ],
      };

  List<String> stagesOf(DeleteForensicTrace? t) =>
      (t?.stages ?? const []).map((s) => s['STAGE'] as String).toList();

  test('A: restore success + local apply success → applied stages', () async {
    await DeleteForensicTraceStore.start(lojaId: 'nathy-pratas-e-folheados');
    final box = await seedProduto();
    StockCatalogBackendService.debugTransport = (name, data) async {
      expect(data['kind'], 'restore');
      return restoreOk(alreadyApplied: false);
    };

    final results =
        await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: 'nathy-pratas-e-folheados',
      itens: [
        {
          'productId': 'nathy-pratas-e-folheados-anel-lacinho-encanto',
          'quantidade': 1,
        }
      ],
      vendaIdParaIdempotencia: '449fc83e-9a5e-4544-9bee-93348123a2dd',
    );
    DeleteForensicTraceStore.stage(DeleteTraceStage.localHiveApplyStart);
    for (final r in results) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: 'nathy-pratas-e-folheados',
        result: r,
      );
    }
    DeleteForensicTraceStore.stage(DeleteTraceStage.localHiveApplySuccess);
    DeleteForensicTraceStore.stage(DeleteTraceStage.remoteRefreshStart);
    DeleteForensicTraceStore.stage(DeleteTraceStage.remoteRefreshSuccess);
    DeleteForensicTraceStore.stage(DeleteTraceStage.saleSoftDeleteStart);
    DeleteForensicTraceStore.stage(DeleteTraceStage.saleSoftDeleteSuccess);
    DeleteForensicTraceStore.endActive(aborted: false);

    final t = DeleteForensicTraceStore.tracesNewestFirst.first;
    final stages = stagesOf(t);
    expect(stages, contains(DeleteTraceStage.deleteStart));
    expect(stages, contains(DeleteTraceStage.restoreCommandHttpSuccess));
    expect(stages, contains(DeleteTraceStage.restoreResultNewlyApplied));
    expect(stages, contains(DeleteTraceStage.restoreResultParsed));
    expect(stages, contains(DeleteTraceStage.restoreResultApplied));
    expect(stages, contains(DeleteTraceStage.localHiveApplySuccess));
    expect(stages, contains(DeleteTraceStage.remoteRefreshSuccess));
    expect(stages, contains(DeleteTraceStage.saleSoftDeleteSuccess));
    expect(t.finalStage, DeleteTraceStage.deleteComplete);
    expect(t.aborted, isFalse);
  });

  test('B: restore success + local apply throws → LOCAL_HIVE_APPLY_ERROR',
      () async {
    await DeleteForensicTraceStore.start(lojaId: 'nathy-pratas-e-folheados');
    StockCatalogBackendService.debugTransport =
        (name, data) async => restoreOk(alreadyApplied: false);

    final results =
        await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: 'nathy-pratas-e-folheados',
      itens: [
        {'productId': 'x', 'quantidade': 1}
      ],
      vendaIdParaIdempotencia: '449fc83e-9a5e-4544-9bee-93348123a2dd',
    );
    expect(results, isNotEmpty);
    DeleteForensicTraceStore.stage(DeleteTraceStage.localHiveApplyStart);
    final err = StateError('forced hive apply failure');
    DeleteForensicTraceStore.captureError(
      DeleteTraceStage.localHiveApplyError,
      err,
      StackTrace.current,
    );
    DeleteForensicTraceStore.captureError(
      DeleteTraceStage.deleteAbort,
      err,
      StackTrace.current,
    );
    DeleteForensicTraceStore.endActive(aborted: true);

    final t = DeleteForensicTraceStore.tracesNewestFirst.first;
    final stages = stagesOf(t);
    expect(stages, contains(DeleteTraceStage.restoreCommandHttpSuccess));
    expect(stages, contains(DeleteTraceStage.localHiveApplyError));
    expect(t.finalStage, DeleteTraceStage.deleteAbort);
    expect(t.aborted, isTrue);
    final hiveErr = t.stages.firstWhere(
      (s) => s['STAGE'] == DeleteTraceStage.localHiveApplyError,
    );
    expect(hiveErr['ERROR_TYPE'], 'StateError');
    expect(hiveErr['STACK_TOP_FRAMES'], isNotEmpty);
  });

  test('C: restore success + remote refresh throws', () async {
    await DeleteForensicTraceStore.start(lojaId: 'nathy-pratas-e-folheados');
    StockCatalogBackendService.debugTransport =
        (name, data) async => restoreOk(alreadyApplied: true);
    await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: 'nathy-pratas-e-folheados',
      itens: [
        {'productId': 'x', 'quantidade': 1}
      ],
      vendaIdParaIdempotencia: '449fc83e-9a5e-4544-9bee-93348123a2dd',
    );
    DeleteForensicTraceStore.stage(DeleteTraceStage.localHiveApplySuccess);
    DeleteForensicTraceStore.stage(DeleteTraceStage.remoteRefreshStart);
    final err = StateError('forced remote refresh failure');
    DeleteForensicTraceStore.captureError(
      DeleteTraceStage.remoteRefreshError,
      err,
      StackTrace.current,
    );
    DeleteForensicTraceStore.captureError(
      DeleteTraceStage.deleteAbort,
      err,
      StackTrace.current,
    );
    DeleteForensicTraceStore.endActive(aborted: true);

    final t = DeleteForensicTraceStore.tracesNewestFirst.first;
    expect(stagesOf(t), contains(DeleteTraceStage.restoreResultIdempotentAlreadyApplied));
    expect(stagesOf(t), contains(DeleteTraceStage.remoteRefreshError));
    expect(t.finalStage, DeleteTraceStage.deleteAbort);
  });

  test('D: restore success + soft-delete throws', () async {
    await DeleteForensicTraceStore.start(lojaId: 'nathy-pratas-e-folheados');
    StockCatalogBackendService.debugTransport =
        (name, data) async => restoreOk(alreadyApplied: true);
    await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: 'nathy-pratas-e-folheados',
      itens: [
        {'productId': 'x', 'quantidade': 1}
      ],
      vendaIdParaIdempotencia: '449fc83e-9a5e-4544-9bee-93348123a2dd',
    );
    DeleteForensicTraceStore.stage(DeleteTraceStage.localHiveApplySuccess);
    DeleteForensicTraceStore.stage(DeleteTraceStage.remoteRefreshSuccess);
    DeleteForensicTraceStore.stage(DeleteTraceStage.saleSoftDeleteStart);
    final err = StateError('forced soft-delete failure');
    DeleteForensicTraceStore.captureError(
      DeleteTraceStage.saleSoftDeleteError,
      err,
      StackTrace.current,
    );
    DeleteForensicTraceStore.endActive(aborted: true);

    final t = DeleteForensicTraceStore.tracesNewestFirst.first;
    expect(stagesOf(t), contains(DeleteTraceStage.saleSoftDeleteError));
    expect(t.finalStage, DeleteTraceStage.deleteAbort);
  });

  test('E: backend restore failure → DELETE_ABORT before hive', () async {
    await DeleteForensicTraceStore.start(lojaId: 'nathy-pratas-e-folheados');
    StockCatalogBackendService.debugTransport = (name, data) async {
      throw StateError('forced backend restore failure');
    };
    Object? caught;
    try {
      await EstoqueTransactionService.devolverEstoqueTransactionBatch(
        lojaId: 'nathy-pratas-e-folheados',
        itens: [
          {'productId': 'x', 'quantidade': 1}
        ],
        vendaIdParaIdempotencia: '449fc83e-9a5e-4544-9bee-93348123a2dd',
      );
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<StateError>());
    DeleteForensicTraceStore.endActive(aborted: true);

    final t = DeleteForensicTraceStore.tracesNewestFirst.first;
    final stages = stagesOf(t);
    expect(stages, contains(DeleteTraceStage.restoreCommandStart));
    expect(stages, contains(DeleteTraceStage.deleteAbort));
    expect(stages, isNot(contains(DeleteTraceStage.localHiveApplyStart)));
    expect(t.finalStage, DeleteTraceStage.deleteAbort);
  });

  test('sanitizeRestoreResponse exposes field availability', () {
    final fields = DeleteForensicTraceStore.sanitizeRestoreResponse(
      restoreOk(alreadyApplied: true),
    );
    expect(fields['alreadyApplied'], isTrue);
    expect(fields['productCount'], 1);
    expect(
      fields['RESTORE_RESPONSE_FIELDS_AVAILABLE'],
      containsAll(['operationId', 'alreadyApplied', 'products']),
    );
  });

  test('mensagemUsuario keeps forensic raw + diagnostic code', () async {
    await DeleteForensicTraceStore.start(lojaId: 'nathy-pratas-e-folheados');
    DeleteForensicTraceStore.captureError(
      DeleteTraceStage.localHiveApplyError,
      StateError('x'),
      StackTrace.current,
    );
    final msg = EstoqueTransactionService.mensagemUsuarioFalhaDevolucaoEstoque(
      StateError('x'),
    );
    expect(msg, contains('Não foi possível devolver o estoque'));
    expect(msg, contains('Código de diagnóstico:'));
  });
}
