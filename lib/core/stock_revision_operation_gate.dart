// Preflight de operações de estoque — bloqueio antes de qualquer escrita (R8.4.1).

import 'package:flutter/foundation.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';

/// Operações que mutam estoque ou dependem do contrato stockRevision.
enum StockRevisionOperationKind {
  venda,
  cancelamento,
  exclusao,
  devolucao,
  entradaManual,
  ajusteAdministrativo,
  consignado,
  combo,
  cadastroProduto,
  importacaoProduto,
}

/// Lançada antes de qualquer escrita quando cliente é incompatível.
class StockRevisionUpdateRequiredException implements Exception {
  StockRevisionUpdateRequiredException(this.message);

  final String message;

  String get code => 'UPDATE_REQUIRED';

  static const String updateRequiredCode = 'UPDATE_REQUIRED';

  @override
  String toString() => 'StockRevisionUpdateRequiredException($code): $message';
}

/// Gate central — testável via overrides sem PackageInfo.
class StockRevisionOperationGate {
  StockRevisionOperationGate._();

  @visibleForTesting
  static int? debugClientBuildNumberOverride;

  @visibleForTesting
  static LegacyStockWriterKind? debugWriterKindOverride;

  @visibleForTesting
  static void resetDebugOverrides() {
    debugClientBuildNumberOverride = null;
    debugWriterKindOverride = null;
  }

  static int resolveClientBuildNumber() {
    return debugClientBuildNumberOverride ?? kMinStockRevisionClientVersion;
  }

  static LegacyStockWriterKind resolveWriterKind() {
    return debugWriterKindOverride ?? LegacyStockWriterKind.newApp;
  }

  /// Fail-closed antes da primeira escrita persistente da operação.
  static void assertAllowed(StockRevisionOperationKind operation) {
    final build = resolveClientBuildNumber();
    final writer = resolveWriterKind();
    if (build < kMinStockRevisionClientVersion) {
      throw StockRevisionUpdateRequiredException(
        'Operação ${operation.name} requer app atualizado '
        '(build $build < $kMinStockRevisionClientVersion).',
      );
    }
    if (writer == LegacyStockWriterKind.legacyApp) {
      throw StockRevisionUpdateRequiredException(
        'Operação ${operation.name} bloqueada: cliente legado sem stockRevision.',
      );
    }
  }
}
