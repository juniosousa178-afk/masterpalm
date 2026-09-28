// Flags da fase 1A. Default desligado: nenhuma UI de produção muda.
// financialLedgerReadOnly existe só como capacidade de diagnóstico interno.
// Não há writer de ledger nesta fase.

abstract final class FinancialV2Flags {
  static const bool financialV2Enabled = false;
  static const bool financialLedgerEnabled = false;

  /// Diagnóstico interno. Não publica navegação nem grava ledger.
  static const bool financialLedgerReadOnly = true;

  static const bool payablesRemoteMirrorEnabled = false;

  /// Piloto 1C: uma loja. Não liga a flag global.
  /// A escrita remota ainda exige
  /// lojas/{id}/financial_v2_pilot/payables.payablesRemoteMirrorEnabled=true.
  static const String payablesRemoteMirrorPilotStoreId =
      'nathy-pratas-e-folheados';
  static const bool cashFlowEnabled = false;

  /// DRE global desligada. O preview da fase 3A é só da loja piloto.
  static const bool dreEnabled = false;
  static const bool financialAccountsEnabled = false;
  static const bool cardReceivablesEnabled = false;

  static const int financialLedgerWrites = 0;
}
