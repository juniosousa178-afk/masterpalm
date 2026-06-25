// Failpoints e idempotência da recuperação assistida.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_import_doc_id_helper.dart';
import 'package:master_palm/services/produto_sync_recovery_access.dart';
import 'package:master_palm/services/produto_sync_recovery_journal_service.dart';
import 'package:master_palm/services/produto_sync_recovery_models.dart';
import 'package:master_palm/services/produto_sync_recovery_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';

import 'support/recovery_failpoint_observer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-atomic';
  late String hivePath;
  late Box<Produto> box;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_atomic_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  Produto p({String slug = 'legado-1'}) => Produto(
        nome: 'Prod Atomic',
        slug: slug,
        custoReal: 1,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 3,
        precoUnitario: 10,
        categoria: 'C',
        dataEntrada: DateTime.now(),
        lojaId: lojaId,
      );

  Future<RecoveryJournalEntry> preparar(Produto prod) async {
    return ProdutoSyncRecoveryJournalService.registrarAntesDeAlterar(
      produto: prod,
      lojaId: lojaId,
      classificacao: RecoveryProdutoClassificacao.elegivelParaRecuperacao,
    );
  }

  RecoveryPreview preview() => RecoveryPreview(
        identity: RecoveryStoreIdentity(
          uidMascarado: 'ab…cd',
          sessaoStoreId: lojaId,
          lojaCanonica: lojaId,
          sessaoDivergeDaCanonica: false,
          ownerUidConfirmado: true,
        ),
        sessionMismatch: RecoverySessionMismatch(
          sessaoStoreId: lojaId,
          lojaCanonica: lojaId,
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

  setUp(() async {
    ProdutoSyncRecoveryAccess.debugForcePodeAcessar = true;
    ProdutoSyncRecoveryAccess.debugForceCanonicalOwner = true;
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
    SyncQueueService.resetProcessRequestCountForTests();
    await ProdutoSyncRecoveryJournalService.resetForTests();
    final boxName = HiveBoxNames.produtos(lojaId);
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box<Produto>(boxName).close();
    }
    box = await Hive.openBox<Produto>(boxName);
    await box.clear();
  });

  tearDown(() async {
    await SyncQueueService.clearQueue();
    await ProdutoSyncRecoveryJournalService.resetForTests();
    if (box.isOpen) {
      await box.clear();
      await box.close();
    }
    const jName = ProdutoSyncRecoveryJournalService.boxName;
    if (Hive.isBoxOpen(jName)) await Hive.box(jName).close();
  });

  test('fail A: após journal produto local intacto', () async {
    final prod = p();
    await box.add(prod);
    final slugAntes = prod.slug;
    final key = prod.key as int;
    final journal = await preparar(prod);

    final r = await ProdutoSyncRecoveryService.recuperarProdutosElegiveis(
      preview: preview(),
      journalEntradas: [journal],
      context: RecoveryExecutionContext(
        observer: RecoveryFailpointObserver(
          RecoveryExecutionCheckpoint.aposJournal,
        ),
      ),
    );

    expect(r.erros, 1);
    expect(prod.slug, slugAntes);
    expect(box.length, 1);
    expect(box.get(key)?.slug, slugAntes);
    final fila = await SyncQueueService.listDiagnosticEntries();
    expect(fila.where((e) => e.entityKey == key), isEmpty);
  });

  test('fail B: slug gerado no journal mas Hive ainda não salvo', () async {
    final prod = p();
    await box.add(prod);
    final slugAntes = prod.slug;
    final journal = await preparar(prod);

    final r = await ProdutoSyncRecoveryService.recuperarProdutosElegiveis(
      preview: preview(),
      journalEntradas: [journal],
      context: RecoveryExecutionContext(
        observer: RecoveryFailpointObserver(
          RecoveryExecutionCheckpoint.aposSlugGerado,
        ),
      ),
    );

    expect(r.erros, 1);
    expect(box.get(prod.key as int)!.slug, slugAntes);
    final j = await ProdutoSyncRecoveryJournalService.buscarPorRecoveryId(
      journal.recoveryId,
    );
    expect(j?.slugNovo, isNotNull);
    expect(
      ProdutoImportDocIdHelper.isDocIdLocalImportacao(j!.slugNovo),
      isTrue,
    );
    expect(j.fase, RecoveryJournalFase.incompletoRequerConfirmacao);
  });

  test('fail C: após save Hive antes de fila', () async {
    final prod = p();
    await box.add(prod);
    final journal = await preparar(prod);

    final r = await ProdutoSyncRecoveryService.recuperarProdutosElegiveis(
      preview: preview(),
      journalEntradas: [journal],
      context: RecoveryExecutionContext(
        observer: RecoveryFailpointObserver(
          RecoveryExecutionCheckpoint.aposSaveHive,
        ),
      ),
    );

    expect(r.erros, 1);
    expect(
      ProdutoImportDocIdHelper.isDocIdLocalImportacao(
        box.get(prod.key as int)!.slug,
      ),
      isTrue,
    );
    final j = await ProdutoSyncRecoveryJournalService.buscarPorRecoveryId(
      journal.recoveryId,
    );
    expect(j?.fase, RecoveryJournalFase.incompletoRequerConfirmacao);
  });

  test('fail D: após fila reconciliada', () async {
    final prod = p();
    await box.add(prod);
    final key = prod.key as int;
    final journal = await preparar(prod);

    final r = await ProdutoSyncRecoveryService.recuperarProdutosElegiveis(
      preview: preview(),
      journalEntradas: [journal],
      context: RecoveryExecutionContext(
        observer: RecoveryFailpointObserver(
          RecoveryExecutionCheckpoint.aposFilaReconciliada,
        ),
      ),
    );

    expect(r.erros, 1);
    final fila = await SyncQueueService.listDiagnosticEntries();
    expect(fila.where((e) => e.entityKey == key).length, 1);
  });

  test('retomada não gera segundo import-uuid', () async {
    final prod = p();
    await box.add(prod);
    final journal = await preparar(prod);

    await ProdutoSyncRecoveryService.recuperarProdutosElegiveis(
      preview: preview(),
      journalEntradas: [journal],
      context: RecoveryExecutionContext(
        observer: RecoveryFailpointObserver(
          RecoveryExecutionCheckpoint.aposSaveHive,
        ),
      ),
    );

    final slugAposFalha = box.get(prod.key as int)!.slug;

    final r2 = await ProdutoSyncRecoveryService.retomarRecuperacaoIncompleta(
      lojaId: lojaId,
    );
    expect(r2.reidentificados, 1);
    expect(box.get(prod.key as int)!.slug, slugAposFalha);
    expect(box.length, 1);
  });

  test('reinício Hive: journal incompleto detectado', () async {
    final prod = p();
    await box.add(prod);
    final journal = await preparar(prod);
    await ProdutoSyncRecoveryJournalService.atualizarFase(
      recoveryId: journal.recoveryId,
      fase: RecoveryJournalFase.incompletoRequerConfirmacao,
      slugNovo: 'import-pendente',
    );

    await Hive.close();
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    await SyncQueueService.init();

    final resumo = await ProdutoSyncRecoveryJournalService.resumoIncompletos(
      lojaId: lojaId,
    );
    expect(resumo.quantidade, greaterThan(0));
    expect(resumo.mensagemSanitizada, contains('pendente'));
  });
}
