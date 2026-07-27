// Preflight de operações de estoque — bloqueio antes de qualquer escrita (R8.4.1).

import 'package:flutter/foundation.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';

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

  static const String userMessage =
      'Esta versão do MasterPalm precisa ser atualizada antes de alterar o estoque.';

  @override
  String toString() => 'StockRevisionUpdateRequiredException($code): $message';
}

/// Gate central — usa build real via [StockRevisionClientBuildResolver].
class StockRevisionOperationGate {
  StockRevisionOperationGate._();

  @visibleForTesting
  static LegacyStockWriterKind? debugWriterKindOverride;

  @visibleForTesting
  static set debugClientBuildNumberOverride(int? value) {
    if (value == null) {
      StockRevisionClientBuildResolver.instance.resetForTest();
    } else {
      StockRevisionClientBuildResolver.instance.setTestOverride(value);
    }
  }

  @visibleForTesting
  static int? get debugClientBuildNumberOverride {
    final state = StockRevisionClientBuildResolver.instance.currentState;
    if (state.source == StockRevisionClientBuildSource.testOverride) {
      return state.parsedBuildNumber;
    }
    return null;
  }

  @visibleForTesting
  static void resetDebugOverrides() {
    StockRevisionClientBuildResolver.instance.resetForTest();
    debugWriterKindOverride = null;
  }

  static int resolveClientBuildNumber() {
    return StockRevisionClientBuildResolver.instance.requireBuildNumber();
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
        '${StockRevisionUpdateRequiredException.userMessage} '
        '(build $build < $kMinStockRevisionClientVersion, operação ${operation.name}).',
      );
    }
    if (writer == LegacyStockWriterKind.legacyApp) {
      throw StockRevisionUpdateRequiredException(
        'Operação ${operation.name} bloqueada: cliente legado sem stockRevision.',
      );
    }
  }
}
