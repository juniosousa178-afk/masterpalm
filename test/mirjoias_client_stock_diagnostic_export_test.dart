import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/mirjoias_client_stock_diagnostic_export.dart';

Produto _p({
  required String id,
  required String code,
  required String nome,
  required int qty,
  int rev = 1,
  String? pendingOp,
  int? pendingBase,
  String? confirmedOp,
  Map<String, dynamic>? variacoes,
  Map<String, int>? ept,
  List<String>? tamanhos,
  String lojaId = 'mirjoias',
}) {
  final p = Produto(
    nome: nome,
    custoReal: 0,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 10,
    quantidade: qty,
    precoUnitario: 10,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 1, 1),
    codigoBarras: code,
    idFirebase: id,
    lojaId: lojaId,
    stockRevision: rev,
    confirmedStockOperationId: confirmedOp,
    pendingStockOperationId: pendingOp,
    pendingStockBaseRevision: pendingBase,
    variacoes: variacoes,
    estoquePorTamanho: ept ?? const {},
    tamanhos: tamanhos ?? const [],
  );
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedRemote({
    required String id,
    required int qty,
    required int rev,
    required String op,
    Map<String, dynamic>? variacoes,
    List<String>? tamanhos,
  }) async {
    await firestore
        .collection('lojas')
        .doc('mirjoias')
        .collection(FSPaths.estoqueProdutosCol)
        .doc(id)
        .set({
      'quantidade': qty,
      'stockRevision': rev,
      'stockOperationId': op,
      'stockKind': variacoes == null ? 'simple' : 'variation',
      'variacoes': variacoes ?? {},
      if (tamanhos != null) 'tamanhos': tamanhos,
    });
  }

  test('1-4. exporter is read-only (no writes / no flush hooks)', () async {
    final p = _p(
      id: 'mirjoias-anel-bolinha-t-25-semijoia-3',
      code: 'AN05SM',
      nome: 'Anel Bolinha T.25 Semijoia',
      qty: 1,
      pendingOp: 'local-pending',
      pendingBase: 1,
      variacoes: {
        '25': {'sem-cor': 1},
      },
      tamanhos: ['25', '16'],
    );
    await seedRemote(
      id: p.idFirebase,
      qty: 1,
      rev: 1,
      op: 'remote-other',
      variacoes: {
        '25': {'sem-cor': 1},
      },
      tamanhos: ['25', '16'],
    );

    final before =
        (await firestore.collection('lojas').doc('mirjoias').collection(FSPaths.estoqueProdutosCol).doc(p.idFirebase).get())
            .data();

    final exporter = MirjoiasClientStockDiagnosticExport(
      firestore: firestore,
      liveBuildId: 'test-build',
      generatedAt: DateTime.utc(2026, 9, 21, 16, 30),
    );
    expect(exporter.writeAttempts, 0);

    final result = await exporter.build(storeId: 'mirjoias', hiveProducts: [p]);
    expect(exporter.writeAttempts, 0);

    final after =
        (await firestore.collection('lojas').doc('mirjoias').collection(FSPaths.estoqueProdutosCol).doc(p.idFirebase).get())
            .data();
    expect(after, before);
    expect(hasPendingStockMutation(p), isTrue);
    expect(result.payload['READ_ONLY'], isTrue);
  });

  test('5-6. restricted to allowlist; other store throws; UI gate', () {
    expect(
      stockDiagnosticExportVisible(
        storeId: 'mirjoias',
        canAccessExistingAdminDiagnostic: true,
      ),
      isTrue,
    );
    expect(
      stockDiagnosticExportVisible(
        storeId: 'nathy-pratas-e-folheados',
        canAccessExistingAdminDiagnostic: true,
      ),
      isTrue,
    );
    expect(
      stockDiagnosticExportVisible(
        storeId: 'nathy-pratas-e-folheados',
        canAccessExistingAdminDiagnostic: false,
      ),
      isFalse,
    );
    expect(
      mirjoiasDiagnosticExportVisible(
        storeId: 'nathy-pratas-e-folheados',
        isAdmin: true,
      ),
      isTrue,
    );

    final exporter = MirjoiasClientStockDiagnosticExport(firestore: firestore);
    expect(
      () => exporter.build(storeId: 'other-store', hiveProducts: const []),
      throwsA(isA<StateError>()),
    );
  });

  test('7. token/auth never enter JSON', () async {
    final p = _p(
      id: 'p1',
      code: 'X1',
      nome: 'X',
      qty: 1,
      pendingOp: 'op-token-test',
      pendingBase: 1,
    );
    await seedRemote(id: 'p1', qty: 1, rev: 1, op: 'remote');
    final exporter = MirjoiasClientStockDiagnosticExport(firestore: firestore);
    final result = await exporter.build(storeId: 'mirjoias', hiveProducts: [p]);
    final json = result.jsonPretty.toLowerCase();
    expect(json.contains('bearer '), isFalse);
    expect(result.payload['redaction']['authToken'], contains('REDACTED'));
    expect(json.contains('eyj'), isFalse);
  });

  test('8/12/13/14. pending box export + orphan/corrupt/multiple', () async {
    final ok = _p(
      id: 'p-ok',
      code: 'A1',
      nome: 'Ok',
      qty: 2,
      pendingOp: 'op-ok',
      pendingBase: 1,
    );
    final corrupt = _p(
      id: 'p-corrupt',
      code: 'A2',
      nome: 'Corrupt',
      qty: 0,
      pendingOp: 'op-no-base',
      pendingBase: null,
    );
    final orphanId = _p(
      id: '',
      code: 'A3',
      nome: 'Orphan',
      qty: 1,
      pendingOp: 'op-orphan',
      pendingBase: 1,
    );
    await seedRemote(id: 'p-ok', qty: 0, rev: 1, op: 'remote-old');

    final exporter = MirjoiasClientStockDiagnosticExport(firestore: firestore);
    final result = await exporter.build(
      storeId: 'mirjoias',
      hiveProducts: [ok, corrupt, orphanId],
    );
    expect(result.payload['PENDING_COUNT'], 3);
    expect((result.payload['pendingMutations'] as List).length, 3);
    expect(result.payload['INVALID_PENDING_COUNT'], greaterThan(0));
    expect(result.payload['ORPHAN_PENDING_COUNT'], greaterThan(0));
    expect(
      (result.payload['PENDING_ZERO_UI_PRODUCTS'] as List)
          .any((e) => e['PRODUCT_CODE'] == 'A2'),
      isTrue,
    );
  });

  test('9-11. remote comparison + AN05SM + delta accounting', () async {
    final an05 = _p(
      id: 'mirjoias-anel-bolinha-t-25-semijoia-3',
      code: 'AN05SM',
      nome: 'Anel Bolinha T.25 Semijoia',
      qty: 1,
      rev: 1,
      pendingOp: 'stale-local',
      pendingBase: 1,
      confirmedOp: 'old',
      variacoes: {
        '25': {'sem-cor': 1},
      },
      tamanhos: ['25', '16'],
    );
    final deltaOnly = _p(
      id: 'mirjoias-delta',
      code: 'DLT1',
      nome: 'Delta Product',
      qty: 5,
      rev: 1,
    );
    await seedRemote(
      id: an05.idFirebase,
      qty: 1,
      rev: 1,
      op: 'd8e222d4-remote',
      variacoes: {
        '25': {'sem-cor': 1},
      },
      tamanhos: ['25', '16'],
    );
    await seedRemote(id: deltaOnly.idFirebase, qty: 2, rev: 1, op: 'r2');

    final exporter = MirjoiasClientStockDiagnosticExport(firestore: firestore);
    final result = await exporter.build(
      storeId: 'mirjoias',
      hiveProducts: [an05, deltaOnly],
    );

    expect(result.payload['AN05SM']['AN05SM_PENDING'], isTrue);
    expect(result.payload['AN05SM']['AN05SM_LOCAL_QTY'], 1);
    expect(result.payload['AN05SM']['AN05SM_REMOTE_QTY'], 1);
    expect(result.payload['AN05SM']['AN05SM_CLASSIFICATION'], 'STALE_PENDING');
    expect(result.payload['AN05SM']['AN05SM_REMOTE_REV_EQUALS_BASE'], isTrue);
    expect(result.payload['AN05SM']['AN05SM_STATE_EQUIVALENT'], isTrue);

    expect(result.payload['HIVE_TOTAL_QTY'], 6);
    expect(result.payload['REMOTE_TOTAL_QTY'], 3);
    expect(result.payload['LOCAL_REMOTE_QTY_DELTA'], 3);
    expect(result.payload['DELTA_ACCOUNTING_PASS'], isTrue);
    expect(result.payload['DELTA_SUM_FROM_PRODUCTS'], 3);

    final orphans = result.payload['ORPHAN_VARIATION_IDENTITIES'] as List;
    expect(orphans.any((e) => e['CODE'] == 'AN05SM' && e['LOCAL_IDENTITY'] == '16'),
        isTrue);
  });

  test('aggregate mismatch codes captured', () async {
    final an13 = _p(
      id: 'mirjoias-an13',
      code: 'AN13PR',
      nome: 'Anel Solitario',
      qty: 4,
      variacoes: {
        '14': {'sem-cor': 1},
        '16': {'sem-cor': 1},
        '21': {'sem-cor': 1},
      },
    );
    await seedRemote(
      id: an13.idFirebase,
      qty: 4,
      rev: 13,
      op: 'r',
      variacoes: {
        '14': {'sem-cor': 1},
        '16': {'sem-cor': 1},
        '21': {'sem-cor': 1},
      },
    );
    final exporter = MirjoiasClientStockDiagnosticExport(firestore: firestore);
    final result =
        await exporter.build(storeId: 'mirjoias', hiveProducts: [an13]);
    final mismatches = result.payload['AGGREGATE_MISMATCHES'] as List;
    expect(mismatches.any((e) => e['CODE'] == 'AN13PR'), isTrue);
    expect(mismatches.first['LOCAL_CELL_SUM'], 3);
    expect(mismatches.first['LOCAL_AGGREGATE'], 4);
  });
}
