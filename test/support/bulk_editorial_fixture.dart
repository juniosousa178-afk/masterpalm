import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Published product with a known price and no Pix/promotion/installments, mirrored in
/// estoque_produtos, draft_produtos, produtos and a Hive box. All in memory.
class BulkEditorialFixture {
  BulkEditorialFixture._(this.db, this.box, this.keys, this.hiveDir);

  static const lojaId = 'loja-bulk-editorial';
  static const outraLoja = 'loja-outra';
  static final t0 = DateTime(2026, 10, 20, 10, 0);

  final FakeFirebaseFirestore db;
  final Box<Produto> box;
  final Map<String, int> keys;
  final Directory hiveDir;

  /// Every callable payload sent while the fixture is active.
  final List<Map<String, dynamic>> commands = [];

  /// Applies an editorial patch like the server: merges it into estoque and draft, then projects
  /// live with draft winning for commercial fields. Throws for ids in [failIds].
  final Set<String> failIds = {};
  Object Function()? failWith;

  static Map<String, dynamic> catalogBase(String id, {bool publicado = true}) => {
        'id': id,
        'nome': 'Produto $id',
        'preco': 100.0,
        'precoFinal': 100.0,
        'categoria': 'Aneis',
        'subcategoria': 'Prata',
        'publicadoNoCatalogo': publicado,
        'emPromocao': false,
        'percentualPromo': null,
        'valorPromo': null,
        'percentualDescontoPix': 0.0,
        'divideSemJuros': false,
        'maxParcelasSemJuros': 12,
        'codigoBarras': 'EAN-$id',
        'imagens': ['https://img/$id.jpg'],
      };

  static Produto produto(String id, {String lojaId = lojaId, bool publicado = true}) => Produto(
        nome: 'Produto $id',
        custoReal: 40,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 100,
        quantidade: 5,
        precoUnitario: 100,
        categoria: 'Aneis',
        subcategoria: 'Prata',
        dataEntrada: DateTime(2026, 10, 1),
        lojaId: lojaId,
        idFirebase: id,
        slug: id,
        codigoBarras: 'EAN-$id',
        imagens: ['https://img/$id.jpg'],
        updatedAt: t0,
        publicadoNoCatalogo: publicado,
        stockRevision: 3,
      );

  static Future<BulkEditorialFixture> create({
    List<String> ids = const ['p1'],
    Set<String> naoPublicados = const {},
    String boxName = 'produtos_bulk_editorial',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final hiveDir = Directory.systemTemp.createTempSync('bulk_editorial_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    final db = FakeFirebaseFirestore();
    final base = db.collection('lojas').doc(lojaId);
    for (final id in ids) {
      final publicado = !naoPublicados.contains(id);
      final editorial = catalogBase(id, publicado: publicado);
      await base.collection('estoque_produtos').doc(id).set({
        ...editorial,
        'lojaId': lojaId,
        'quantidade': 5,
        'custoReal': 40.0,
        'stockRevision': 3,
        'stockOperationId': 'op-anterior-$id',
        'updatedAt': Timestamp.fromDate(t0),
      });
      await base.collection('draft_produtos').doc(id).set({
        ...editorial..remove('codigoBarras'),
        'ativo': true,
        'publicar': publicado,
      });
      if (publicado) {
        await base.collection('produtos').doc(id).set({
          ...catalogBase(id)..remove('codigoBarras'),
          'ativo': true,
          'publicar': true,
          'quantidade': 5,
        });
      }
    }
    ProdutosFirestoreService.debugFirestoreOverride = db;
    final box = await Hive.openBox<Produto>(boxName);
    final keys = <String, int>{};
    for (final id in ids) {
      keys[id] = await box.add(produto(id, publicado: !naoPublicados.contains(id)));
    }
    final f = BulkEditorialFixture._(db, box, keys, hiveDir);
    StockCatalogBackendService.debugTransport = f._serverEmulator;
    return f;
  }

  Future<Map<String, dynamic>> _serverEmulator(String name, Map<String, dynamic> data) async {
    commands.add({'name': name, ...data});
    if (name != 'stockCatalogCommand' || data['kind'] != 'editorial') {
      throw UnsupportedError('emulator only applies editorial commands');
    }
    final items = (data['items'] as List).cast<Map>();
    final id = items.single['productId'] as String;
    if (failIds.contains(id)) throw failWith?.call() ?? StateError('fail $id');
    final base = db.collection('lojas').doc(data['lojaId'] as String);
    final stockRef = base.collection('estoque_produtos').doc(id);
    final draftRef = base.collection('draft_produtos').doc(id);
    final stock = await stockRef.get();
    final draft = await draftRef.get();
    if (!stock.exists || !draft.exists) {
      throw StateError('Canonical product and editorial draft required');
    }
    final patch = Map<String, dynamic>.from(data['editorial'] as Map);
    await stockRef.set({...stock.data()!, ...patch});
    final draftData = {...draft.data()!, ...patch};
    await draftRef.set(draftData);
    final stockData = (await stockRef.get()).data()!;
    final liveRef = base.collection('produtos').doc(id);
    if (draftData['publicadoNoCatalogo'] == true && (stockData['quantidade'] as num) > 0) {
      final live = (await liveRef.get()).data() ?? {};
      await liveRef.set({...live, ...draftData, 'quantidade': stockData['quantidade']});
    }
    return {
      'alreadyApplied': false,
      'operationId': data['operationId'],
      'products': [
        {
          'productId': id,
          'quantidade': stockData['quantidade'],
          'stockRevision': stockData['stockRevision'],
        }
      ],
    };
  }

  Future<Map<String, dynamic>?> doc(String col, String id, {String loja = lojaId}) async =>
      (await db.collection('lojas').doc(loja).collection(col).doc(id).get()).data();

  Future<void> dispose() async {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    StockCatalogBackendService.debugTransport = null;
    CatalogoSyncService.debugFirestoreOverride = null;
    await box.close();
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  }
}
