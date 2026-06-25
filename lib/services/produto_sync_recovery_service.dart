// Execução controlada da recuperação de produtos elegíveis (com confirmação explícita).

import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'produto_import_doc_id_helper.dart';
import 'produto_sync_recovery_access.dart';
import 'produto_sync_recovery_journal_service.dart';
import 'produto_sync_recovery_models.dart';
import 'produto_sync_recovery_preview_service.dart';
import 'sync_queue_service.dart';

class ProdutoSyncRecoveryService {
  ProdutoSyncRecoveryService._();

  /// Prepara journal de backup para todos os elegíveis do preview.
  static Future<RecoveryPrepareResult> prepararRecuperacao(
    RecoveryPreview preview,
  ) async {
    if (!await ProdutoSyncRecoveryAccess.podeAcessarRecuperacao()) {
      return const RecoveryPrepareResult(
        sucesso: false,
        entradasJournal: [],
        mensagem: 'Sem permissão',
      );
    }

    if (!preview.identity.sessaoAlinhada) {
      return const RecoveryPrepareResult(
        sucesso: false,
        entradasJournal: [],
        mensagem: 'Sessão não alinhada com a loja canônica',
      );
    }

    final lojaId = preview.identity.lojaCanonica;
    if (lojaId == null || lojaId.isEmpty) {
      return const RecoveryPrepareResult(
        sucesso: false,
        entradasJournal: [],
        mensagem: 'Loja canônica indisponível',
      );
    }

    final box = await _abrirProdutosBox(lojaId);
    if (box == null) {
      return const RecoveryPrepareResult(
        sucesso: false,
        entradasJournal: [],
        mensagem: 'Box de produtos indisponível',
      );
    }

    final entradas = <RecoveryJournalEntry>[];
    for (final item in preview.elegiveisLista) {
      final produto = box.get(item.entityKey);
      if (produto == null) continue;

      try {
        final entry =
            await ProdutoSyncRecoveryJournalService.registrarAntesDeAlterar(
          produto: produto,
          lojaId: lojaId,
          classificacao: item.classificacao,
        );
        entradas.add(entry);
      } catch (_) {}
    }

    return RecoveryPrepareResult(
      sucesso: entradas.isNotEmpty,
      entradasJournal: entradas,
      mensagem: entradas.isEmpty
          ? 'Nenhuma entrada nova no journal'
          : '${entradas.length} produto(s) preparado(s)',
    );
  }

  /// Retoma journals incompletos explicitamente (idempotente por recoveryId).
  static Future<RecoveryExecuteResult> retomarRecuperacaoIncompleta({
    required String lojaId,
    RecoveryExecutionContext context = const RecoveryExecutionContext(),
  }) async {
    if (!await ProdutoSyncRecoveryAccess.podeAcessarRecuperacao()) {
      return const RecoveryExecuteResult(
        sucesso: false,
        reidentificados: 0,
        ignorados: 0,
        erros: 0,
        mensagem: 'Sem permissão',
      );
    }

    final incompletos = (await ProdutoSyncRecoveryJournalService.listarEntradas(
      lojaId: lojaId,
      apenasIncompletas: true,
    ))
        .where(
          (e) => e.fase == RecoveryJournalFase.incompletoRequerConfirmacao,
        )
        .toList();
    if (incompletos.isEmpty) {
      return const RecoveryExecuteResult(
        sucesso: false,
        reidentificados: 0,
        ignorados: 0,
        erros: 0,
        mensagem: 'Nenhuma recuperação pendente',
      );
    }

    return _executarJournals(
      lojaId: lojaId,
      journals: incompletos,
      remoteDocIds: const {},
      context: context,
    );
  }

  /// Reidentifica produtos elegíveis com journal prévio e enfileira sync.
  static Future<RecoveryExecuteResult> recuperarProdutosElegiveis({
    required RecoveryPreview preview,
    required List<RecoveryJournalEntry> journalEntradas,
    RecoveryExecutionContext context = const RecoveryExecutionContext(),
  }) async {
    if (!await ProdutoSyncRecoveryAccess.podeAcessarRecuperacao()) {
      return const RecoveryExecuteResult(
        sucesso: false,
        reidentificados: 0,
        ignorados: 0,
        erros: 0,
        mensagem: 'Sem permissão',
      );
    }

    if (!preview.identity.sessaoAlinhada) {
      return const RecoveryExecuteResult(
        sucesso: false,
        reidentificados: 0,
        ignorados: 0,
        erros: 0,
        mensagem: 'Sessão não alinhada',
      );
    }

    if (journalEntradas.isEmpty) {
      return const RecoveryExecuteResult(
        sucesso: false,
        reidentificados: 0,
        ignorados: 0,
        erros: 0,
        mensagem: 'Backup journal não concluído',
      );
    }

    final lojaId = preview.identity.lojaCanonica!;
    return _executarJournals(
      lojaId: lojaId,
      journals: journalEntradas,
      remoteDocIds: preview.remoteDocIdsConhecidos,
      context: context,
    );
  }

  static Future<RecoveryExecuteResult> _executarJournals({
    required String lojaId,
    required List<RecoveryJournalEntry> journals,
    required Set<String> remoteDocIds,
    required RecoveryExecutionContext context,
  }) async {
    final box = await _abrirProdutosBox(lojaId);
    if (box == null) {
      return const RecoveryExecuteResult(
        sucesso: false,
        reidentificados: 0,
        ignorados: 0,
        erros: 1,
        mensagem: 'Box indisponível',
      );
    }

    final vendasBoxName = HiveBoxNames.vendas(lojaId);
    Box<Venda>? vendasBox;
    try {
      if (Hive.isBoxOpen(vendasBoxName)) {
        vendasBox = Hive.box<Venda>(vendasBoxName);
      } else {
        vendasBox = await Hive.openBox<Venda>(vendasBoxName);
      }
    } catch (_) {}

    var reidentificados = 0;
    var ignorados = 0;
    var erros = 0;

    await SyncQueueService.runWithDeferredQueueProcessing(() async {
      for (final journal in journals) {
        if (journal.fase == RecoveryJournalFase.concluido) {
          ignorados++;
          continue;
        }

        final produto = box.get(journal.entityKey);
        if (produto == null) {
          await ProdutoSyncRecoveryJournalService.marcarIncompleto(
            journal.recoveryId,
          );
          erros++;
          continue;
        }

        final classificacaoAtual =
            await ProdutoSyncRecoveryPreviewService.classificarProdutoLocal(
          produto: produto,
          lojaCanonica: lojaId,
          remoteDocIds: remoteDocIds,
          todosProdutos: box.values.toList(),
          vendasBox: vendasBox,
        );

        if (classificacaoAtual !=
                RecoveryProdutoClassificacao.elegivelParaRecuperacao &&
            journal.fase == RecoveryJournalFase.prepared) {
          ignorados++;
          continue;
        }

        try {
          final concluiu = await _executarJournalFaseado(
            produto: produto,
            lojaId: lojaId,
            remoteDocIds: remoteDocIds,
            journal: journal,
            context: context,
          );
          if (concluiu) {
            reidentificados++;
          } else {
            ignorados++;
          }
        } catch (_) {
          await ProdutoSyncRecoveryJournalService.marcarIncompleto(
            journal.recoveryId,
          );
          erros++;
        }
      }
    });

    if (reidentificados > 0) {
      await _observerCheckpoint(
        context,
        RecoveryExecutionCheckpoint.aposAgendarProcessamento,
        journals.first,
      );
      SyncQueueService.requestProcessWhenOnline(lojaId: lojaId);
    }

    return RecoveryExecuteResult(
      sucesso: reidentificados > 0 && erros == 0,
      reidentificados: reidentificados,
      ignorados: ignorados,
      erros: erros,
      mensagem: reidentificados > 0
          ? '$reidentificados produto(s) reidentificado(s)'
          : 'Nenhum produto reidentificado',
    );
  }

  static Future<bool> _executarJournalFaseado({
    required Produto produto,
    required String lojaId,
    required Set<String> remoteDocIds,
    required RecoveryJournalEntry journal,
    required RecoveryExecutionContext context,
  }) async {
    final key = produto.key;
    if (key is! int) throw StateError('entityKey inválida');

    var entry = await ProdutoSyncRecoveryJournalService.buscarPorRecoveryId(
          journal.recoveryId,
        ) ??
        journal;

    if (entry.fase == RecoveryJournalFase.concluido) return true;

    await _observerCheckpoint(
      context,
      RecoveryExecutionCheckpoint.aposJournal,
      entry,
    );

    final tinhaAckRemoto = produto.idFirebase.trim().isNotEmpty &&
        remoteDocIds.contains(produto.idFirebase.trim());

    if (_faseOrdinal(entry.fase) <
        _faseOrdinal(RecoveryJournalFase.produtoReidentificado)) {
      final slugNovo = entry.slugNovo ??
          ProdutoImportDocIdHelper.gerarDocIdLocalSeguro();
      entry = await ProdutoSyncRecoveryJournalService.atualizarFase(
        recoveryId: entry.recoveryId,
        fase: RecoveryJournalFase.prepared,
        slugNovo: slugNovo,
      );

      await _observerCheckpoint(
        context,
        RecoveryExecutionCheckpoint.aposSlugGerado,
        entry,
      );

      produto.slug = slugNovo;
      if (!tinhaAckRemoto) {
        produto.idFirebase = '';
      }
      produto.lojaId = lojaId;
      await produto.save();

      await _observerCheckpoint(
        context,
        RecoveryExecutionCheckpoint.aposSaveHive,
        entry,
      );

      entry = await ProdutoSyncRecoveryJournalService.atualizarFase(
        recoveryId: entry.recoveryId,
        fase: RecoveryJournalFase.produtoReidentificado,
        slugNovo: slugNovo,
      );
    } else if (entry.slugNovo != null &&
        entry.slugNovo!.isNotEmpty &&
        produto.slug != entry.slugNovo) {
      produto.slug = entry.slugNovo!;
      if (!tinhaAckRemoto) produto.idFirebase = '';
      produto.lojaId = lojaId;
      await produto.save();
    }

    if (_faseOrdinal(entry.fase) <
        _faseOrdinal(RecoveryJournalFase.filaReconciliada)) {
      final jaNaFila = await SyncQueueService.hasPendingProdutoSync(
        lojaId: lojaId,
        entityKey: key,
        includeDeadLetter: false,
      );
      if (!jaNaFila) {
        await SyncQueueService.enqueueProdutoUnico(
          lojaId: lojaId,
          boxName: HiveBoxNames.produtos(lojaId),
          entityKey: key,
          scheduleProcess: false,
        );
      }

      entry = await ProdutoSyncRecoveryJournalService.atualizarFase(
        recoveryId: entry.recoveryId,
        fase: RecoveryJournalFase.filaReconciliada,
        slugNovo: entry.slugNovo,
      );

      await _observerCheckpoint(
        context,
        RecoveryExecutionCheckpoint.aposFilaReconciliada,
        entry,
      );
    }

    entry = await ProdutoSyncRecoveryJournalService.atualizarFase(
      recoveryId: entry.recoveryId,
      fase: RecoveryJournalFase.prontoParaSync,
      slugNovo: entry.slugNovo,
    );

    entry = await ProdutoSyncRecoveryJournalService.atualizarFase(
      recoveryId: entry.recoveryId,
      fase: RecoveryJournalFase.concluido,
      slugNovo: entry.slugNovo,
    );

    return true;
  }

  static int _faseOrdinal(RecoveryJournalFase fase) {
    switch (fase) {
      case RecoveryJournalFase.prepared:
      case RecoveryJournalFase.incompletoRequerConfirmacao:
        return 0;
      case RecoveryJournalFase.produtoReidentificado:
        return 1;
      case RecoveryJournalFase.filaReconciliada:
        return 2;
      case RecoveryJournalFase.prontoParaSync:
        return 3;
      case RecoveryJournalFase.concluido:
        return 4;
    }
  }

  static Future<void> _observerCheckpoint(
    RecoveryExecutionContext context,
    RecoveryExecutionCheckpoint checkpoint,
    RecoveryJournalEntry entry,
  ) async {
    await context.observer?.onCheckpoint(checkpoint, entry);
  }

  static Future<Box<Produto>?> _abrirProdutosBox(String lojaId) async {
    final name = HiveBoxNames.produtos(lojaId);
    try {
      if (Hive.isBoxOpen(name)) return Hive.box<Produto>(name);
      return await Hive.openBox<Produto>(name);
    } catch (_) {
      return null;
    }
  }
}
