/// Classificação explícita da fonte. Impede a UI de tratar Hive local
/// como verdade remota sincronizada.
enum FinancialAuthority {
  /// Firestore (ou comando remoto) é a autoridade depois do sync.
  remoteAuthoritative,

  /// Só existe no aparelho. Ex.: contas a pagar.
  localOnly,

  /// Número calculado a partir de outras fontes. Não é um documento.
  derived,

  /// Foto congelada (fechamento). Não é recalculada.
  snapshot,
}
