// Helpers exclusivos de teste — inicialização explícita do build do cliente (R8.4.8).

import 'package:master_palm/core/stock_revision_client_build_resolver.dart';

/// Limpa override e estado do resolver (não inicializado).
void resetStockClientBuildForTest() {
  StockRevisionClientBuildResolver.instance.resetForTest();
}

/// Configura build compatível explicitamente para testes de escrita.
void initializeCompatibleStockClientBuildForTest([int buildNumber = 285]) {
  StockRevisionClientBuildResolver.instance.setTestOverride(buildNumber);
}

/// Simula parsing de raw build (ex.: cenários fail-closed).
void initializeStockClientBuildFromRawForTest(String rawBuildNumber) {
  StockRevisionClientBuildResolver.instance.initializeFromRawForTest(
    rawBuildNumber,
  );
}
