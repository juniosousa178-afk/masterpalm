// Contrato futuro do ledger. Fase 1A não grava.
// FINANCIAL_LEDGER_WRITES=0

import 'financial_v2_flags.dart';

enum FinancialLedgerEventType {
  saleAccrual,
  saleReversal,
  receivableCreated,
  receivablePayment,
  receivableReversal,
  payableCreated,
  payablePayment,
  expense,
  income,
  transferOut,
  transferIn,
  adjustment,
}

class FinancialLedgerIdempotencyKey {
  const FinancialLedgerIdempotencyKey({
    required this.storeId,
    required this.originType,
    required this.originOperationId,
    required this.eventType,
  });

  final String storeId;
  final String originType;
  final String originOperationId;
  final FinancialLedgerEventType eventType;

  /// storeId + originType + originOperationId + eventType
  String get value {
    final store = storeId.trim();
    final origin = originType.trim();
    final op = originOperationId.trim();
    if (store.isEmpty || origin.isEmpty || op.isEmpty) {
      throw ArgumentError('Chave de idempotência incompleta.');
    }
    return '$store|$origin|$op|${eventType.name}';
  }
}

class FinancialLedgerWriteForbidden implements Exception {
  const FinancialLedgerWriteForbidden();

  @override
  String toString() => 'FinancialLedgerWriteForbidden';
}

/// Taxa estimada da config não pode entrar num ledger imutável.
class EstimatedCardFeeLedgerRejected implements Exception {
  const EstimatedCardFeeLedgerRejected();
}

abstract final class FinancialLedgerContract {
  static const int writes = FinancialV2Flags.financialLedgerWrites;

  static Never rejectWrite() {
    throw const FinancialLedgerWriteForbidden();
  }

  static void rejectEstimatedCardFee() {
    throw const EstimatedCardFeeLedgerRejected();
  }

  /// Transferência move saldo entre contas. Não é receita nem despesa.
  static bool countsAsRevenue(FinancialLedgerEventType type) {
    return type == FinancialLedgerEventType.saleAccrual ||
        type == FinancialLedgerEventType.income;
  }

  static bool countsAsExpense(FinancialLedgerEventType type) {
    return type == FinancialLedgerEventType.expense;
  }

  static bool countsAsTransfer(FinancialLedgerEventType type) {
    return type == FinancialLedgerEventType.transferIn ||
        type == FinancialLedgerEventType.transferOut;
  }
}
