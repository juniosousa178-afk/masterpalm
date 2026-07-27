// Bootstrap do resolvedor de build do cliente (R8.4.6).

import 'package:master_palm/core/stock_revision_client_build_resolver.dart';

/// Garante inicialização antes de qualquer operação de estoque.
class StockRevisionClientBuildBootstrap {
  StockRevisionClientBuildBootstrap._();

  static Future<void> ensureInitialized() {
    return StockRevisionClientBuildResolver.instance.initialize();
  }
}
