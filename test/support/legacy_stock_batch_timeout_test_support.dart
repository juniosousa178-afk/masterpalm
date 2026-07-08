import 'dart:async';

/// Simula o timeout externo de 25s removido em 15040bc — somente testes RED/STOCKTO.
class LegacyStockBatchTimeoutTestSupport {
  static const legacyUserMessage =
      'Transação de estoque demorou muito. Tente novamente.';

  static Future<T> withLegacyBatchTimeout<T>(
    Future<T> future, {
    Duration duration = const Duration(seconds: 25),
  }) {
    return future.timeout(
      duration,
      onTimeout: () => throw TimeoutException(legacyUserMessage),
    );
  }
}
