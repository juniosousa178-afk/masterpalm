// Testes atualizados da recuperação assistida (gates base).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/firestore_access_guard.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produto_import_doc_id_helper.dart';
import 'package:master_palm/services/produto_sync_recovery_access.dart';
import 'package:master_palm/services/produto_sync_recovery_journal_service.dart';
import 'package:master_palm/services/produto_sync_recovery_mask_util.dart';
import 'package:master_palm/services/produto_sync_recovery_models.dart';
import 'package:master_palm/services/produto_sync_recovery_preview_service.dart';
import 'package:master_palm/services/produto_sync_recovery_service.dart';
import 'package:master_palm/services/produto_sync_recovery_session_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/tombstone_firestore_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaCanonica = 'loja-recovery-canon';
  const lojaSessao = 'loja-recovery-sessao';
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Venda> vendasBox;

  Venda vendaComItem({required String productId, required String nome}) {
    return Venda(
      clienteNome: 'C',
      produtosDescricao: nome,
      quantidade: 1,
      preco: 10,
      total: 10,
      formasPagamento: 'Dinheiro',
      data: DateTime.now(),
      vendedor: 'V',
      observacao: '',
      lojaId: lojaCanonica,
      itens: [
        VendaItem(
          produtoNome: nome,
          quantidade: 1,
          precoUnitario: 10,
          productId: productId,
          lojaId: lojaCanonica,
        ),
      ],
    );
  }

  Produto prod({
    required String nome,
    String slug = '',
    String idFirebase = '',
    String lojaId = lojaCanonica,
    String tipo = 'simples',
    List<Map<String, dynamic>>? itensCombo,
  }) {
    return Produto(
      nome: nome,
      slug: slug,
      idFirebase: idFirebase,
      custoReal: 1,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 10,
      quantidade: 1,
      precoUnitario: 10,
      categoria: 'Cat',
      dataEntrada: DateTime.now(),
      lojaId: lojaId,
      tipoProduto: tipo,
      itensCombo: itensCombo,
    );
  }

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_recovery_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoSyncRecoveryAccess.resetForTests();
    ProdutoSyncRecoveryPreviewService.resetDebugOverridesForTests();
    ProdutosFirestoreService.debugForbidFirestoreAccess = true;
    FirestoreAccessGuard.resetForTests();
    SyncQueueService.resetProcessRequestCountForTests();

    final prodName = HiveBoxNames.produtos(lojaCanonica);
    final vendName = HiveBoxNames.vendas(lojaCanonica);
    if (Hive.isBoxOpen(prodName)) {
      await Hive.box(prodName).clear();
      await Hive.box(prodName).close();
    }
    if (Hive.isBoxOpen(vendName)) {
      await Hive.box(vendName).clear();
      await Hive.box(vendName).close();
    }
    produtosBox = await Hive.openBox<Produto>(prodName);
    vendasBox = await Hive.openBox<Venda>(vendName);
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
    await ProdutoSyncRecoveryJournalService.resetForTests();
    await ProdutoSyncRecoverySessionService.resetHistoryForTests();

    ProdutoSyncRecoveryAccess.debugForcePodeAcessar = true;
    ProdutoSyncRecoveryAccess.debugForceCanonicalOwner = true;
    ProdutoSyncRecoveryPreviewService.debugRemoteDocIdsOverride = {'remoto-1'};
  });

  tearDown(() async {
    limparTombstoneFake();
    ProdutosFirestoreService.debugForbidFirestoreAccess = false;
    ProdutoSyncRecoveryPreviewService.resetDebugOverridesForTests();
    await SyncQueueService.clearQueue();
    await produtosBox.close();
    await vendasBox.close();
  });

  test('classificação preview não altera Hive nem fila', () async {
    final p = prod(nome: 'A', slug: 'legado-tomb');
    await produtosBox.add(p);
    final slugAntes = p.slug;

    await ProdutoSyncRecoveryPreviewService.classificarProdutoLocal(
      produto: p,
      lojaCanonica: lojaCanonica,
      remoteDocIds: {},
      todosProdutos: [p],
      vendasBox: vendasBox,
    );

    expect(p.slug, slugAntes);
  });

  test('journal fase prepared ao preparar', () async {
    final p = prod(nome: 'J', slug: 'slug-j');
    await produtosBox.add(p);
    final j = await ProdutoSyncRecoveryJournalService.registrarAntesDeAlterar(
      produto: p,
      lojaId: lojaCanonica,
      classificacao: RecoveryProdutoClassificacao.elegivelParaRecuperacao,
    );
    expect(j.fase, RecoveryJournalFase.prepared);
    expect(p.slug, 'slug-j');
  });

  test('produto elegível recebe import-{uuid} e fase concluido', () async {
    final p = prod(nome: 'Novo', slug: 'loja-recovery-canon-novo');
    await produtosBox.add(p);
    final journal = await ProdutoSyncRecoveryJournalService.registrarAntesDeAlterar(
      produto: p,
      lojaId: lojaCanonica,
      classificacao: RecoveryProdutoClassificacao.elegivelParaRecuperacao,
    );

    final preview = RecoveryPreview(
      identity: RecoveryStoreIdentity(
        uidMascarado: 'x',
        sessaoStoreId: lojaCanonica,
        lojaCanonica: lojaCanonica,
        sessaoDivergeDaCanonica: false,
      ),
      sessionMismatch: RecoverySessionMismatch(
        sessaoStoreId: lojaCanonica,
        lojaCanonica: lojaCanonica,
        podeReparar: false,
      ),
      produtosLocaisSessao: 1,
      produtosLocaisCanonica: 1,
      produtosRemotos: 0,
      tombstones: 0,
      filaPendentes: 0,
      filaDeadLetter: 0,
      filaItens: const [],
      produtos: const [],
      offline: true,
    );

    await ProdutoSyncRecoveryService.recuperarProdutosElegiveis(
      preview: preview,
      journalEntradas: [journal],
    );

    expect(ProdutoImportDocIdHelper.isDocIdLocalImportacao(p.slug), isTrue);
    final j = await ProdutoSyncRecoveryJournalService.buscarPorRecoveryId(
      journal.recoveryId,
    );
    expect(j?.fase, RecoveryJournalFase.concluido);
  });

  test('tombstone via fake firestore classifica elegível', () async {
    final fake = FakeFirebaseFirestore();
    await registrarTombstoneRemotoFake(
      firestore: fake,
      lojaId: lojaCanonica,
      estoqueDocId: 'tombo-legado',
    );
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = fake;

    final p = prod(nome: 'Tombo', slug: 'tombo-legado');
    await produtosBox.add(p);

    final c = await ProdutoSyncRecoveryPreviewService.classificarProdutoLocal(
      produto: p,
      lojaCanonica: lojaCanonica,
      remoteDocIds: {},
      todosProdutos: [p],
      vendasBox: vendasBox,
    );
    expect(c, RecoveryProdutoClassificacao.elegivelParaRecuperacao);
  });

  test('requestProcessWhenOnline exige lojaId', () async {
    SyncQueueService.requestProcessWhenOnline(lojaId: lojaCanonica);
    expect(SyncQueueService.debugProcessRequestCount, 1);
    expect(FirestoreAccessGuard.accessCount, 0);
  });

  test('mascaramento não expõe UID completo', () {
    expect(
      ProdutoSyncRecoveryMaskUtil.mascararUid('57YhMPjFH6SV5Nbig2eUp0BrbOw1'),
      isNot(contains('57YhMPjFH6SV5Nbig2eUp0BrbOw1')),
    );
  });
}
