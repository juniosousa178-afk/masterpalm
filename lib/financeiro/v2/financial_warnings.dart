/// Avisos que impedem apresentar um número como se estivesse completo.
abstract final class FinancialDataQualityWarning {
  static const payablesLocalOnly = 'PAYABLES_LOCAL_ONLY';
  static const historicalSaleMissingCogs = 'HISTORICAL_SALE_MISSING_COGS';
  static const consignmentCogsUnknown = 'CONSIGNMENT_COGS_UNKNOWN';
  static const cardFeeEstimatedOnly = 'CARD_FEE_ESTIMATED_ONLY';
  static const noFinancialAccounts = 'NO_FINANCIAL_ACCOUNTS';
  static const noOpeningBalance = 'NO_OPENING_BALANCE';
  static const incompleteCostData = 'INCOMPLETE_COST_DATA';
}
