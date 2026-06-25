// Modelos para preview e recuperação assistida de sincronização de estoque.

/// Fases do journal de recuperação assistida.
enum RecoveryJournalFase {
  prepared,
  produtoReidentificado,
  filaReconciliada,
  prontoParaSync,
  incompletoRequerConfirmacao,
  concluido,
}

extension RecoveryJournalFaseLabel on RecoveryJournalFase {
  bool get isTerminal => this == RecoveryJournalFase.concluido;

  bool get isIncompleto =>
      this != RecoveryJournalFase.concluido &&
      this != RecoveryJournalFase.prontoParaSync;
}

/// Checkpoints internos da execução (observador opcional; não persiste em produção).
enum RecoveryExecutionCheckpoint {
  aposJournal,
  aposSlugGerado,
  aposSaveHive,
  aposFilaReconciliada,
  aposAgendarProcessamento,
}

/// Observador opcional para testes de failpoint (injetado explicitamente).
abstract class RecoveryExecutionObserver {
  Future<void> onCheckpoint(
    RecoveryExecutionCheckpoint checkpoint,
    RecoveryJournalEntry entry,
  );
}

/// Contexto opcional de execução da recuperação.
class RecoveryExecutionContext {
  const RecoveryExecutionContext({this.observer});

  final RecoveryExecutionObserver? observer;
}

/// Classificação de um produto local no fluxo de recuperação.
enum RecoveryProdutoClassificacao {
  jaSincronizado,
  elegivelParaRecuperacao,
  comVendaOuReferencia,
  comVinculoCombo,
  conflitoRemoto,
  tombstoneLegado,
  filaLojaDivergente,
  lojaDivergente,
  dadosInsuficientes,
  recuperacaoManualNecessaria,
}

extension RecoveryProdutoClassificacaoLabel on RecoveryProdutoClassificacao {
  String get rotuloCurto {
    switch (this) {
      case RecoveryProdutoClassificacao.jaSincronizado:
        return 'Já sincronizado';
      case RecoveryProdutoClassificacao.elegivelParaRecuperacao:
        return 'Elegível para recuperação';
      case RecoveryProdutoClassificacao.comVendaOuReferencia:
        return 'Com venda ou referência';
      case RecoveryProdutoClassificacao.comVinculoCombo:
        return 'Vínculo de combo';
      case RecoveryProdutoClassificacao.conflitoRemoto:
        return 'Conflito remoto';
      case RecoveryProdutoClassificacao.tombstoneLegado:
        return 'Tombstone legado';
      case RecoveryProdutoClassificacao.filaLojaDivergente:
        return 'Fila em loja divergente';
      case RecoveryProdutoClassificacao.lojaDivergente:
        return 'Outra loja';
      case RecoveryProdutoClassificacao.dadosInsuficientes:
        return 'Dados insuficientes';
      case RecoveryProdutoClassificacao.recuperacaoManualNecessaria:
        return 'Recuperação manual necessária';
    }
  }
}

/// Identidade de loja para diagnóstico de recuperação.
class RecoveryStoreIdentity {
  const RecoveryStoreIdentity({
    required this.uidMascarado,
    required this.sessaoStoreId,
    required this.lojaCanonica,
    required this.sessaoDivergeDaCanonica,
    this.ownerUidConfirmado = false,
  });

  final String uidMascarado;
  final String? sessaoStoreId;
  final String? lojaCanonica;
  final bool sessaoDivergeDaCanonica;
  final bool ownerUidConfirmado;

  bool get sessaoAlinhada =>
      !sessaoDivergeDaCanonica &&
      sessaoStoreId != null &&
      lojaCanonica != null &&
      sessaoStoreId == lojaCanonica;
}

/// Divergência de sessão detectada no preview.
class RecoverySessionMismatch {
  const RecoverySessionMismatch({
    required this.sessaoStoreId,
    required this.lojaCanonica,
    required this.podeReparar,
    this.motivoBloqueio,
  });

  final String? sessaoStoreId;
  final String? lojaCanonica;
  final bool podeReparar;
  final String? motivoBloqueio;
}

/// Item resumido da fila no preview.
class RecoveryQueueItem {
  const RecoveryQueueItem({
    required this.entityKey,
    required this.lojaId,
    required this.deadLetter,
    required this.erroSanitizado,
    required this.lojaDivergente,
  });

  final int entityKey;
  final String lojaId;
  final bool deadLetter;
  final String? erroSanitizado;
  final bool lojaDivergente;
}

/// Produto local classificado no preview.
class RecoveryProdutoItem {
  const RecoveryProdutoItem({
    required this.entityKey,
    required this.nomeMascarado,
    required this.classificacao,
    this.motivoSanitizado,
    this.temFilaPendente = false,
    this.filaDeadLetter = false,
  });

  final int entityKey;
  final String nomeMascarado;
  final RecoveryProdutoClassificacao classificacao;
  final String? motivoSanitizado;
  final bool temFilaPendente;
  final bool filaDeadLetter;
}

/// Resultado read-only do preview de recuperação.
class RecoveryPreview {
  const RecoveryPreview({
    required this.identity,
    required this.sessionMismatch,
    required this.produtosLocaisSessao,
    required this.produtosLocaisCanonica,
    required this.produtosRemotos,
    required this.tombstones,
    required this.filaPendentes,
    required this.filaDeadLetter,
    required this.filaItens,
    required this.produtos,
    required this.offline,
    this.erroRemotoSanitizado,
    this.remoteDocIdsConhecidos = const {},
    this.journalIncompleto,
  });

  final RecoveryStoreIdentity identity;
  final RecoverySessionMismatch sessionMismatch;
  final int produtosLocaisSessao;
  final int produtosLocaisCanonica;
  final int? produtosRemotos;
  final int? tombstones;
  final int filaPendentes;
  final int filaDeadLetter;
  final List<RecoveryQueueItem> filaItens;
  final List<RecoveryProdutoItem> produtos;
  final bool offline;
  final String? erroRemotoSanitizado;
  final Set<String> remoteDocIdsConhecidos;
  final RecoveryJournalIncompletoResumo? journalIncompleto;

  int get elegiveis => produtos
      .where((p) =>
          p.classificacao == RecoveryProdutoClassificacao.elegivelParaRecuperacao)
      .length;

  int get manuais => produtos
      .where((p) =>
          p.classificacao ==
              RecoveryProdutoClassificacao.recuperacaoManualNecessaria ||
          p.classificacao ==
              RecoveryProdutoClassificacao.comVendaOuReferencia ||
          p.classificacao == RecoveryProdutoClassificacao.comVinculoCombo ||
          p.classificacao == RecoveryProdutoClassificacao.conflitoRemoto)
      .length;

  List<RecoveryProdutoItem> get elegiveisLista => produtos
      .where((p) =>
          p.classificacao == RecoveryProdutoClassificacao.elegivelParaRecuperacao)
      .toList();
}

/// Resumo de journals incompletos detectados no preview.
class RecoveryJournalIncompletoResumo {
  const RecoveryJournalIncompletoResumo({
    required this.quantidade,
    required this.mensagemSanitizada,
  });

  final int quantidade;
  final String mensagemSanitizada;
}

/// Histórico de reparo de sessão local.
class RecoverySessionRepairRecord {
  const RecoverySessionRepairRecord({
    required this.storeIdAnterior,
    required this.storeIdNovo,
    required this.timestampMs,
    required this.motivo,
  });

  final String storeIdAnterior;
  final String storeIdNovo;
  final int timestampMs;
  final String motivo;

  Map<String, dynamic> toMap() => {
        'storeIdAnterior': storeIdAnterior,
        'storeIdNovo': storeIdNovo,
        'timestampMs': timestampMs,
        'motivo': motivo,
      };

  factory RecoverySessionRepairRecord.fromMap(Map<String, dynamic> m) =>
      RecoverySessionRepairRecord(
        storeIdAnterior: (m['storeIdAnterior'] ?? '').toString(),
        storeIdNovo: (m['storeIdNovo'] ?? '').toString(),
        timestampMs: (m['timestampMs'] as num?)?.toInt() ?? 0,
        motivo: (m['motivo'] ?? '').toString(),
      );
}

/// Entrada do journal de backup antes da reidentificação.
class RecoveryJournalEntry {
  const RecoveryJournalEntry({
    required this.recoveryId,
    required this.entityKey,
    required this.lojaId,
    required this.nomeMascarado,
    required this.slugAnterior,
    required this.idFirebaseAnterior,
    required this.sku,
    required this.codigoBarras,
    required this.timestampMs,
    required this.classificacao,
    required this.estadoDaFila,
    this.fase = RecoveryJournalFase.prepared,
    this.slugNovo,
    this.aplicado = false,
  });

  final String recoveryId;
  final int entityKey;
  final String lojaId;
  final String nomeMascarado;
  final String slugAnterior;
  final String idFirebaseAnterior;
  final String sku;
  final String codigoBarras;
  final int timestampMs;
  final RecoveryProdutoClassificacao classificacao;
  final String? estadoDaFila;
  final RecoveryJournalFase fase;
  final String? slugNovo;
  final bool aplicado;

  Map<String, dynamic> toMap() => {
        'recoveryId': recoveryId,
        'entityKey': entityKey,
        'lojaId': lojaId,
        'nomeMascarado': nomeMascarado,
        'slugAnterior': slugAnterior,
        'idFirebaseAnterior': idFirebaseAnterior,
        'sku': sku,
        'codigoBarras': codigoBarras,
        'timestampMs': timestampMs,
        'classificacao': classificacao.name,
        'estadoDaFila': estadoDaFila,
        'fase': fase.name,
        'slugNovo': slugNovo,
        'aplicado': aplicado || fase == RecoveryJournalFase.concluido,
      };

  factory RecoveryJournalEntry.fromMap(Map<String, dynamic> m) =>
      RecoveryJournalEntry(
        recoveryId: (m['recoveryId'] ?? '').toString(),
        entityKey: (m['entityKey'] as num?)?.toInt() ?? 0,
        lojaId: (m['lojaId'] ?? '').toString(),
        nomeMascarado: (m['nomeMascarado'] ?? '').toString(),
        slugAnterior: (m['slugAnterior'] ?? '').toString(),
        idFirebaseAnterior: (m['idFirebaseAnterior'] ?? '').toString(),
        sku: (m['sku'] ?? '').toString(),
        codigoBarras: (m['codigoBarras'] ?? '').toString(),
        timestampMs: (m['timestampMs'] as num?)?.toInt() ?? 0,
        classificacao: RecoveryProdutoClassificacao.values.firstWhere(
          (e) => e.name == m['classificacao'],
          orElse: () => RecoveryProdutoClassificacao.dadosInsuficientes,
        ),
        estadoDaFila: m['estadoDaFila']?.toString(),
        fase: RecoveryJournalFase.values.firstWhere(
          (e) => e.name == m['fase'],
          orElse: () => (m['aplicado'] == true)
              ? RecoveryJournalFase.concluido
              : RecoveryJournalFase.prepared,
        ),
        slugNovo: m['slugNovo']?.toString(),
        aplicado: m['aplicado'] == true,
      );

  RecoveryJournalEntry copyWith({
    bool? aplicado,
    RecoveryJournalFase? fase,
    String? slugNovo,
  }) =>
      RecoveryJournalEntry(
        recoveryId: recoveryId,
        entityKey: entityKey,
        lojaId: lojaId,
        nomeMascarado: nomeMascarado,
        slugAnterior: slugAnterior,
        idFirebaseAnterior: idFirebaseAnterior,
        sku: sku,
        codigoBarras: codigoBarras,
        timestampMs: timestampMs,
        classificacao: classificacao,
        estadoDaFila: estadoDaFila,
        fase: fase ?? this.fase,
        slugNovo: slugNovo ?? this.slugNovo,
        aplicado: aplicado ?? this.aplicado,
      );
}

/// Resultado da preparação (backup journal) antes da recuperação.
class RecoveryPrepareResult {
  const RecoveryPrepareResult({
    required this.sucesso,
    required this.entradasJournal,
    this.mensagem,
  });

  final bool sucesso;
  final List<RecoveryJournalEntry> entradasJournal;
  final String? mensagem;
}

/// Resultado da execução da recuperação de produtos elegíveis.
class RecoveryExecuteResult {
  const RecoveryExecuteResult({
    required this.sucesso,
    required this.reidentificados,
    required this.ignorados,
    required this.erros,
    this.mensagem,
  });

  final bool sucesso;
  final int reidentificados;
  final int ignorados;
  final int erros;
  final String? mensagem;
}
