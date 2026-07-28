// Enforcement cliente — bloqueia escritores legados antes de mutar grade (R8.4).

import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';

/// Versão mínima do app que exige contrato stockRevision em mutações de grade.
const int kMinStockRevisionClientVersion = 284;

/// Código de rejeição para UX / diagnóstico.
class StockRevisionWriteRejectedException implements Exception {
  StockRevisionWriteRejectedException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'StockRevisionWriteRejected($code): $message';
}

bool stockWritePayloadChangesGrade(
  Map<String, dynamic> updateData, {
  Map<String, dynamic>? existingData,
}) {
  if (existingData == null || existingData.isEmpty) {
    return updateData.containsKey('quantidade') ||
        updateData.containsKey('variacoes') ||
        updateData.containsKey('estoquePorTamanho') ||
        updateData.containsKey('estoquePorCor');
  }
  final remoteGrade = ProdutoEstoqueGradeSnapshot.fromRemote(existingData);
  final merged = Map<String, dynamic>.from(existingData)..addAll(updateData);
  final nextGrade = ProdutoEstoqueGradeSnapshot.fromRemote(merged);
  return nextGrade.gradeDiffersFrom(remoteGrade);
}

/// Fail-closed antes de qualquer write Firestore que altere grade.
void enforceStockRevisionWriteContract({
  required Map<String, dynamic> updateData,
  Map<String, dynamic>? existingData,
  LegacyStockWriterKind writer = LegacyStockWriterKind.newApp,
}) {
  final clientBuildNumber =
      StockRevisionClientBuildResolver.instance.requireBuildNumber();
  if (clientBuildNumber < kMinStockRevisionClientVersion) {
    throw StockRevisionWriteRejectedException(
      'LEGACY_CLIENT_FORCED_UPDATE',
      'Atualize o aplicativo para continuar alterando estoque.',
    );
  }

  if (writer == LegacyStockWriterKind.legacyApp) {
    throw StockRevisionWriteRejectedException(
      'LEGACY_WRITER_BLOCKED',
      'Escritor legado não pode alterar grade sem stockRevision.',
    );
  }

  if (!stockWritePayloadChangesGrade(updateData, existingData: existingData)) {
    return;
  }

  if (!updateData.containsKey(kProdutoStockRevisionField) ||
      !updateData.containsKey(kProdutoStockOperationIdField)) {
    throw StockRevisionWriteRejectedException(
      'MISSING_REVISION_FIELDS',
      'Mutação de grade exige stockRevision e stockOperationId.',
    );
  }

  final newRev = parseStockRevisionFromRemote(updateData);
  final prevRev = parseStockRevisionFromRemote(existingData);
  final newOp = parseStockOperationIdFromRemote(updateData);
  if (newOp == null || newOp.isEmpty) {
    throw StockRevisionWriteRejectedException(
      'MISSING_OPERATION_ID',
      'Mutação de grade exige stockOperationId não vazio.',
    );
  }

  if (existingData != null && existingData.isNotEmpty) {
    if (newRev < prevRev) {
      throw StockRevisionWriteRejectedException(
        'REVISION_REGRESSION',
        'stockRevision não pode regredir ($newRev < $prevRev).',
      );
    }
    if (newRev == prevRev) {
      final prevOp = parseStockOperationIdFromRemote(existingData);
      if (prevOp != newOp) {
        throw StockRevisionWriteRejectedException(
          'SAME_REVISION_DIFFERENT_GRADE',
          'Grade diferente na mesma stockRevision.',
        );
      }
    } else if (newRev != prevRev + 1) {
      throw StockRevisionWriteRejectedException(
        'REVISION_JUMP',
        'stockRevision deve incrementar exatamente +1 ($prevRev → $newRev).',
      );
    }
  }
}
