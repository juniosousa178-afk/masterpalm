// Flags da fase 1A. Default desligado: nenhuma UI de produção muda.
// financialLedgerReadOnly existe só como capacidade de diagnóstico interno.
// Não há writer de ledger nesta fase.

abstract final class FinancialV2Flags {
  static const bool financialV2Enabled = false;
  static const bool financialLedgerEnabled = false;

  /// Diagnóstico interno. Não publica navegação nem grava ledger.
  static const bool financialLedgerReadOnly = true;

  static const bool payablesRemoteMirrorEnabled = false;
  static const bool cashFlowEnabled = false;
  static const bool dreEnabled = false;
  static const bool financialAccountsEnabled = false;
  static const bool cardReceivablesEnabled = false;

  static const int financialLedgerWrites = 0;
}
