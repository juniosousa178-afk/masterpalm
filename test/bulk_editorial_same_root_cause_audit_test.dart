import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';

import 'support/bulk_editorial_fixture.dart';

// Bulk category/subcategory still use Hive change + syncProdutosPorChavesHive + catalogoWeb sync:
// the catalog is updated for published products; unpublished ones stay only in Hive remotely.
// Pix, dividir sem juros and promotion activation moved to BulkEditorialService.
const _loja = BulkEditorialFixture.lojaId;

void main() {
  late BulkEditorialFixture f;

  setUp(() async {
    f = await BulkEditorialFixture.create(ids: ['pub', 'nopub'], naoPublicados: {'nopub'});
  });
  tearDown(() => f.dispose());

  Future<void> legacyBulk(void Function(dynamic p) change, List<String> ids) async {
    for (final id in ids) {
      final p = f.box.get(f.keys[id])!;
      change(p);
      await p.save();
    }
    await ProdutosFirestoreService.syncProdutosPorChavesHive(
      box: f.box,
      lojaId: _loja,
      hiveKeys: [for (final id in ids) f.keys[id]!],
    );
  }

  Future<void> legacyCatalogoWeb(List<String> ids) async {
    for (final id in ids) {
      final p = f.box.get(f.keys[id])!;
      if (!p.publicadoNoCatalogo) continue;
      p.updatedAt = DateTime.now();
      await p.save();
      await CatalogoSyncService.syncProduto(p, target: SyncTarget.draft, lojaIdOverride: _loja);
      await CatalogoSyncService.syncProduto(p,
          target: SyncTarget.live, lojaIdOverride: _loja, removerSeSemEstoque: true);
    }
  }

  test('categoria em lote: publicado chega ao servidor; não publicado fica só no Hive', () async {
    await legacyBulk((p) => p.categoria = 'Colares', ['pub', 'nopub']);
    await legacyCatalogoWeb(['pub', 'nopub']);
    final enviados = f.commands.map((c) => (c['items'] as List).single['productId']).toSet();
    expect(enviados, {'pub'});
    expect(f.commands.every((c) => c['kind'] == 'editorial'), isTrue);
    expect((await f.doc('produtos', 'pub'))!['categoria'], 'Colares');
    expect((await f.doc('estoque_produtos', 'nopub'))!['categoria'], 'Aneis');
    expect((await f.doc('draft_produtos', 'nopub'))!['categoria'], 'Aneis');
    expect(f.box.get(f.keys['nopub'])!.categoria, 'Colares');
  });

  test('subcategoria em lote: mesmo comportamento da categoria', () async {
    await legacyBulk((p) => p.subcategoria = 'Ouro', ['pub', 'nopub']);
    await legacyCatalogoWeb(['pub', 'nopub']);
    expect((await f.doc('produtos', 'pub'))!['subcategoria'], 'Ouro');
    expect((await f.doc('estoque_produtos', 'nopub'))!['subcategoria'], 'Prata');
  });
}
