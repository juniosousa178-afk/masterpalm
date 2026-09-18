import 'package:flutter/foundation.dart';

/// Client mirror of `parseCommand` in `functions/src/stockCatalogCommands.js`:
/// `new Set(items.map(i => i.productId)).size > MAX_PRODUCTS`.
///
/// Does not change the server guard. Sale and restock commands are counted
/// independently — never unioned for the 25-product gate.
class StockCatalogAffectedProducts {
  StockCatalogAffectedProducts._();

  static const int maxAffectedProducts = 25;
  static const String errorCategory = 'SAVED_SALE_EDIT_SIZE_LIMIT';
  static const String userTitle = 'Não foi possível salvar a alteração';

  /// Distinct non-empty `productId` values. Variation cells / duplicate lines
  /// of the same id count once.
  static int distinctProductIdCount(Iterable<Map<String, dynamic>> items) {
    final ids = <String>{};
    for (final item in items) {
      final id = _productIdOf(item);
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.length;
  }

  static String _productIdOf(Map<String, dynamic> item) {
    final raw = item['productId'] ?? item['produtosId'] ?? item['id'] ?? '';
    return raw.toString().trim();
  }

  static int _signedQtyOf(Map<String, dynamic> item) {
    return (item['quantidade'] as num?)?.toInt() ??
        (item['quantity'] as num?)?.toInt() ??
        (item['qty'] as num?)?.toInt() ??
        0;
  }

  /// Signed edit delta: `quantidade < 0` → sale command, `> 0` → restock.
  static ({int sale, int restock}) countsFromSignedDelta(
    Iterable<Map<String, dynamic>> signedItems,
  ) {
    final sale = <String>{};
    final restock = <String>{};
    for (final item in signedItems) {
      final id = _productIdOf(item);
      if (id.isEmpty) continue;
      final qty = _signedQtyOf(item);
      if (qty < 0) {
        sale.add(id);
      } else if (qty > 0) {
        restock.add(id);
      }
    }
    return (sale: sale.length, restock: restock.length);
  }

  static bool exceedsLimit(int count) => count > maxAffectedProducts;

  static bool commandsExceedLimit({
    required int saleCount,
    required int restockCount,
  }) =>
      exceedsLimit(saleCount) || exceedsLimit(restockCount);

  static void assertCommandsWithinLimit({
    required int saleCount,
    required int restockCount,
    bool originalSaleUnchanged = true,
  }) {
    if (!commandsExceedLimit(saleCount: saleCount, restockCount: restockCount)) {
      return;
    }
    debugPrint(
      '[$errorCategory] sale=$saleCount restock=$restockCount '
      'limit=$maxAffectedProducts',
    );
    throw SavedSaleStockSizeLimitException(
      saleCount: saleCount,
      restockCount: restockCount,
      originalSaleUnchanged: originalSaleUnchanged,
    );
  }

  static void assertSignedDeltaWithinLimit(
    Iterable<Map<String, dynamic>> signedItems, {
    bool originalSaleUnchanged = true,
  }) {
    final counts = countsFromSignedDelta(signedItems);
    assertCommandsWithinLimit(
      saleCount: counts.sale,
      restockCount: counts.restock,
      originalSaleUnchanged: originalSaleUnchanged,
    );
  }

  static void assertItemMapsWithinLimit(
    Iterable<Map<String, dynamic>> items, {
    int restockCount = 0,
    bool originalSaleUnchanged = true,
  }) {
    assertCommandsWithinLimit(
      saleCount: distinctProductIdCount(items),
      restockCount: restockCount,
      originalSaleUnchanged: originalSaleUnchanged,
    );
  }

  static String userMessage({
    required int saleCount,
    required int restockCount,
    bool originalSaleUnchanged = true,
    bool countsKnown = true,
  }) {
    final saleOver = exceedsLimit(saleCount);
    final restockOver = exceedsLimit(restockCount);
    final buf = StringBuffer();
    if (!countsKnown) {
      buf.writeln(
        'Esta edição altera o estoque de mais produtos do que o permitido '
        'em uma única operação. O limite atual é de $maxAffectedProducts produtos.',
      );
    } else if (saleOver && restockOver) {
      buf.writeln(
        'Saída: $saleCount produtos; devolução: $restockCount produtos; '
        'limite por operação: $maxAffectedProducts.',
      );
    } else {
      final n = saleOver ? saleCount : restockCount;
      buf.writeln(
        'Esta edição altera o estoque de $n produtos em uma única operação. '
        'O limite atual é de $maxAffectedProducts produtos.',
      );
    }
    if (originalSaleUnchanged) {
      buf.writeln('A venda original não foi alterada.');
    }
    buf.write('Revise a alteração ou cancele a edição.');
    return buf.toString().trim();
  }

  static bool isLimitUserMessage(String message) {
    final lower = message.toLowerCase();
    return lower.contains('limite atual é de $maxAffectedProducts') ||
        lower.contains('limite por operação: $maxAffectedProducts') ||
        lower.contains('mais produtos do que o permitido');
  }

  static bool isBackendAffectedLimit(Object error) {
    if (error is SavedSaleStockSizeLimitException) return true;
    final text = error.toString().toLowerCase();
    if (text.contains('too many affected products')) return true;
    try {
      final dyn = error as dynamic;
      final code = dyn.code?.toString().toLowerCase();
      final message = (dyn.message ?? '').toString().toLowerCase();
      if (code == 'resource-exhausted' &&
          message.contains('too many affected products')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  static String userMessageForError(Object error) {
    if (error is SavedSaleStockSizeLimitException) return error.userMessage;
    return userMessage(
      saleCount: 0,
      restockCount: 0,
      originalSaleUnchanged: true,
      countsKnown: false,
    );
  }
}

class SavedSaleStockSizeLimitException implements Exception {
  final int saleCount;
  final int restockCount;
  final bool originalSaleUnchanged;

  const SavedSaleStockSizeLimitException({
    required this.saleCount,
    required this.restockCount,
    this.originalSaleUnchanged = true,
  });

  String get userTitle => StockCatalogAffectedProducts.userTitle;

  String get userMessage => StockCatalogAffectedProducts.userMessage(
        saleCount: saleCount,
        restockCount: restockCount,
        originalSaleUnchanged: originalSaleUnchanged,
      );

  @override
  String toString() => userMessage;
}
