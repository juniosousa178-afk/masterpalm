// Política explícita para escrita inline em produtos/{id} durante sync de estoque.

/// Controla se [ProdutosFirestoreService.syncProdutoComStatus] executa
/// `upsert_produtos_live_inline` no mesmo ciclo.
enum CatalogoLiveInlinePolicy {
  /// Comportamento legado: escreve em `produtos` após salvar estoque.
  executar,

  /// Formulário de produto com pós-save canônico (draft + live) garantido.
  ignorarPorquePosSaveCanonico,
}
