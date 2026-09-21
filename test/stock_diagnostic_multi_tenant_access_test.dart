import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/catalogo_sync_diagnostics_access.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/mirjoias_client_stock_diagnostic_export.dart';

Produto _p({
  required String id,
  required String code,
  required String nome,
  required int qty,
  required String lojaId,
}) {
  return Produto(
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
    stockRevision: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    CatalogoSyncDiagnosticsAccess.resetForTests();
  });

  group('access gates', () {
    test('1-3 MIRJOIAS owner/admin visible; common hidden', () {
      expect(
        stockDiagnosticExportVisible(
          storeId: 'mirjoias',
          canAccessExistingAdminDiagnostic: true,
        ),
        isTrue,
      );
      expect(
        stockDiagnosticExportVisible(
          storeId: 'mirjoias',
          canAccessExistingAdminDiagnostic: false,
        ),
        isFalse,
      );
    });

    test('4-6 NATHY owner/admin visible; common hidden', () {
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
    });

    test('7 other store owner/admin hidden', () {
      expect(
        stockDiagnosticExportVisible(
          storeId: 'zivejoias',
          canAccessExistingAdminDiagnostic: true,
        ),
        isFalse,
      );
      expect(isAllowedDiagnosticTenant('master'), isFalse);
    });

    test('8-11 mobile/desktop use same gate (layout-agnostic)', () {
      // Drawer único web/mobile: visibilidade não depende de platform.
      for (final store in [
        kMirjoiasDiagnosticStoreId,
        kNathyDiagnosticStoreId,
      ]) {
        expect(
          stockDiagnosticExportVisible(
            storeId: store,
            canAccessExistingAdminDiagnostic: true,
          ),
          isTrue,
        );
      }
    });

    test('canAccessStockDiagnosticExport uses catalog admin predicate', () async {
      CatalogoSyncDiagnosticsAccess.debugForcePodeAcessar = true;
      expect(
        await canAccessStockDiagnosticExport(storeId: 'mirjoias'),
        isTrue,
      );
      expect(
        await canAccessStockDiagnosticExport(
          storeId: 'nathy-pratas-e-folheados',
        ),
        isTrue,
      );
      CatalogoSyncDiagnosticsAccess.debugForcePodeAcessar = false;
      expect(
        await canAccessStockDiagnosticExport(storeId: 'mirjoias'),
        isFalse,
      );
      expect(
        await canAccessStockDiagnosticExport(storeId: 'zivejoias'),
        isFalse,
      );
    });
  });

  group('tenant isolation', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    Future<void> seed(String loja, String id, int qty) async {
      await firestore
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({
        'quantidade': qty,
        'stockRevision': 1,
        'stockOperationId': 'op-$id',
        'stockKind': 'simple',
      });
    }

    test('MIRJOIAS export excludes Nathy products', () async {
      final mir = _p(
        id: 'mirjoias-anel-x',
        code: 'M1',
        nome: 'Mir',
        qty: 2,
        lojaId: 'mirjoias',
      );
      final nathy = _p(
        id: 'nathy-pratas-e-folheados-anel-y',
        code: 'N1',
        nome: 'Nathy',
        qty: 9,
        lojaId: 'nathy-pratas-e-folheados',
      );
      await seed('mirjoias', mir.idFirebase, 2);

      final exporter =
          MirjoiasClientStockDiagnosticExport(firestore: firestore);
      final result = await exporter.build(
        storeId: 'mirjoias',
        hiveProducts: [mir, nathy],
      );

      expect(result.jsonFileName, startsWith('MIRJOIAS_CLIENT_STOCK_DIAGNOSTIC_'));
      expect(result.payload['storeId'], 'mirjoias');
      expect(result.payload['TENANT_ISOLATION'], isTrue);
      final hive = result.payload['hiveProducts'] as List;
      expect(hive.length, 1);
      expect(hive.first['LOCAL_PRODUCT_ID'], mir.idFirebase);
      final json = result.jsonPretty;
      expect(json.contains('nathy-pratas-e-folheados'), isFalse);
      expect(json.contains('Nathy'), isFalse);
    });

    test('NATHY export excludes MIRJOIAS products', () async {
      final mir = _p(
        id: 'mirjoias-anel-x',
        code: 'M1',
        nome: 'Mir',
        qty: 2,
        lojaId: 'mirjoias',
      );
      final nathy = _p(
        id: 'nathy-pratas-e-folheados-anel-y',
        code: 'N1',
        nome: 'Nathy Piece',
        qty: 9,
        lojaId: 'nathy-pratas-e-folheados',
      );
      await seed('nathy-pratas-e-folheados', nathy.idFirebase, 9);

      final exporter =
          MirjoiasClientStockDiagnosticExport(firestore: firestore);
      final result = await exporter.build(
        storeId: 'nathy-pratas-e-folheados',
        hiveProducts: [mir, nathy],
      );

      expect(result.jsonFileName, startsWith('NATHY_CLIENT_STOCK_DIAGNOSTIC_'));
      expect(result.jsonFileName.endsWith('.json'), isTrue);
      expect(result.downloadArtifacts, hasLength(1));
      expect(result.payload['storeId'], 'nathy-pratas-e-folheados');
      expect(result.payload['summary'], isA<Map>());
      expect(result.payload['summary']['SINGLE_FILE_EXPORT'], isTrue);
      final hive = result.payload['hiveProducts'] as List;
      expect(hive.length, 1);
      expect(hive.first['LOCAL_PRODUCT_ID'], nathy.idFirebase);
      final json = result.jsonPretty.toLowerCase();
      expect(json.contains('mirjoias-anel'), isFalse);
      expect(json.contains('"storeid": "mirjoias"'), isFalse);
    });
  });

  test('file prefixes', () {
    expect(
      stockDiagnosticFilePrefix('mirjoias'),
      'MIRJOIAS_CLIENT_STOCK_DIAGNOSTIC',
    );
    expect(
      stockDiagnosticFilePrefix('nathy-pratas-e-folheados'),
      'NATHY_CLIENT_STOCK_DIAGNOSTIC',
    );
  });
}
