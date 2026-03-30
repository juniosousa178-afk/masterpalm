/// Ordem de exibição das avaliações no catálogo público (configurável na loja).
enum CatalogAvaliacoesOrdem {
  maisRecentes,
  maisAntigas,
  melhorAvaliadas,
  pioresAvaliadas,
  nomeAz,
  nomeZa;

  /// Valor salvo em Firestore (`lojas/.../config` ou documento de loja).
  String get firestoreValue => switch (this) {
        CatalogAvaliacoesOrdem.maisRecentes => 'mais_recentes',
        CatalogAvaliacoesOrdem.maisAntigas => 'mais_antigas',
        CatalogAvaliacoesOrdem.melhorAvaliadas => 'melhor_avaliadas',
        CatalogAvaliacoesOrdem.pioresAvaliadas => 'piores_avaliadas',
        CatalogAvaliacoesOrdem.nomeAz => 'nome_az',
        CatalogAvaliacoesOrdem.nomeZa => 'nome_za',
      };

  /// Rótulo para telas de configuração (PT).
  String get labelConfig => switch (this) {
        CatalogAvaliacoesOrdem.maisRecentes => 'Mais recentes primeiro',
        CatalogAvaliacoesOrdem.maisAntigas => 'Mais antigas primeiro',
        CatalogAvaliacoesOrdem.melhorAvaliadas => 'Melhor avaliadas (estrelas)',
        CatalogAvaliacoesOrdem.pioresAvaliadas => 'Menor nota primeiro',
        CatalogAvaliacoesOrdem.nomeAz => 'Nome do cliente (A–Z)',
        CatalogAvaliacoesOrdem.nomeZa => 'Nome do cliente (Z–A)',
      };

  static CatalogAvaliacoesOrdem fromFirestore(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase().replaceAll(' ', '_') ?? '';
    return switch (s) {
      'mais_antigas' || 'antigas' => CatalogAvaliacoesOrdem.maisAntigas,
      'melhor_avaliadas' ||
      'estrelas_desc' ||
      'maior_nota' =>
        CatalogAvaliacoesOrdem.melhorAvaliadas,
      'piores_avaliadas' ||
      'menor_nota' ||
      'estrelas_asc' =>
        CatalogAvaliacoesOrdem.pioresAvaliadas,
      'nome_az' || 'nome_a_z' => CatalogAvaliacoesOrdem.nomeAz,
      'nome_za' || 'nome_z_a' => CatalogAvaliacoesOrdem.nomeZa,
      _ => CatalogAvaliacoesOrdem.maisRecentes,
    };
  }
}
