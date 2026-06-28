// Metadados persistidos na fila para publicação canônica draft → live.

/// Plano de publicação do catálogo para um item [SyncOperationType.upsertProduto].
enum CatalogoQueuePublishPlan {
  /// Comportamento legado: estoque + inline em produtos/{id}.
  legadoInline,

  /// Formulário: estoque, depois draft e live canônicos (sem inline).
  canonicoAposEstoque,
}

/// Fase atual da máquina de estados canônica na fila.
enum CatalogoQueuePublishPhase {
  aguardandoEstoque,
  aguardandoDraft,
  aguardandoLive,
}

/// Origens sanitizadas permitidas em [SyncQueueItem.catalogoQueueSourceOrigin].
abstract final class CatalogoQueueSourceOrigins {
  static const produtoFormSave = 'produto_form.save';
  static const produtoFormPersistirAtual = 'produto_form.persistir_atual';
  static const legada = 'outra_origem_legada';

  static String sanitizar(String? writeOrigin) {
    final o = (writeOrigin ?? '').trim();
    if (o == produtoFormSave || o == produtoFormPersistirAtual) return o;
    if (o.startsWith('produto_form.')) {
      return o.length <= 64 ? o : '${o.substring(0, 64)}…';
    }
    return legada;
  }
}
