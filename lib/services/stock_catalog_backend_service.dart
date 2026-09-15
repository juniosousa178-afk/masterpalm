import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Protocol transport only. Balances and publication decisions belong to server.
class StockCatalogBackendService {
  StockCatalogBackendService._();

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(
      String name, Map<String, dynamic> data)? debugTransport;

  static Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (debugTransport != null) return debugTransport!(name, data);
    final result =
        await FirebaseFunctions.instanceFor(region: 'southamerica-east1')
            .httpsCallable(name)
            .call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  static String _id(String value) {
    if (value.isEmpty || value.trim() != value || value.contains('/')) {
      throw ArgumentError('Identificador de estoque inválido');
    }
    return value;
  }

  static Future<Map<String, dynamic>> publishOne(
          String lojaId, String productId) =>
      _call('catalogPublishOne',
          {'lojaId': _id(lojaId), 'productId': _id(productId)});

  static Future<Map<String, dynamic>> publishAll(String lojaId) =>
      _call('catalogPublishAll', {'lojaId': _id(lojaId)});

  static String orderSaleOperationId(String orderId) =>
      'order_${sha256.convert(utf8.encode(_id(orderId)))}';

  static Future<Map<String, dynamic>> orderSale(
          String lojaId, String orderId) =>
      _call('stockCatalogOrderSale',
          {'lojaId': _id(lojaId), 'orderId': _id(orderId)});

  static Future<Map<String, dynamic>> deleteProduct(
    String lojaId,
    String productId, {
    required int expectedRevision,
    String? operationId,
  }) =>
      command(
        lojaId: lojaId,
        operationId: (operationId ?? '').trim().isEmpty
            ? 'delete_${sha256.convert(utf8.encode('${_id(lojaId)}|${_id(productId)}|$expectedRevision'))}'
            : operationId!.trim(),
        kind: 'delete',
        items: [
          {'productId': _id(productId), 'expectedRevision': expectedRevision}
        ],
      );

  static Future<Map<String, dynamic>> undoDeleteProduct(
    String lojaId,
    String productId, {
    required int expectedRevision,
    String? operationId,
  }) =>
      command(
        lojaId: lojaId,
        operationId: (operationId ?? '').trim().isEmpty
            ? 'undo_${sha256.convert(utf8.encode('${_id(lojaId)}|${_id(productId)}|$expectedRevision'))}'
            : operationId!.trim(),
        kind: 'undo',
        items: [
          {'productId': _id(productId), 'expectedRevision': expectedRevision}
        ],
      );

  static Future<Map<String, dynamic>> tombstoneVariation({
    required String lojaId,
    required String productId,
    required int expectedRevision,
    required List<String> keys,
    String? operationId,
  }) =>
      command(
        lojaId: lojaId,
        operationId: (operationId ?? '').trim().isEmpty
            ? 'tvar_${sha256.convert(utf8.encode('${_id(lojaId)}|${_id(productId)}|${keys.join(',')}|$expectedRevision'))}'
            : operationId!.trim(),
        kind: 'tombstoneVariation',
        items: [
          {'productId': _id(productId), 'expectedRevision': expectedRevision}
        ],
        tombstoneKeys: keys,
      );

  static Future<Map<String, dynamic>> clearVariationTombstone({
    required String lojaId,
    required String productId,
    required int expectedRevision,
    required List<String> keys,
    String? operationId,
  }) =>
      command(
        lojaId: lojaId,
        operationId: (operationId ?? '').trim().isEmpty
            ? 'cvar_${sha256.convert(utf8.encode('${_id(lojaId)}|${_id(productId)}|${keys.join(',')}|$expectedRevision'))}'
            : operationId!.trim(),
        kind: 'clearVariationTombstone',
        items: [
          {'productId': _id(productId), 'expectedRevision': expectedRevision}
        ],
        tombstoneKeys: keys,
      );

  /// Mirrors the server editorial allowlist; stock and recipe fields never enter this payload.
  static const editorialFields = <String>{
    'nome',
    'descricao',
    'descricao_curta',
    'preco',
    'preco_venda',
    'precoFinal',
    'precoPorTamanho',
    'imagens',
    'imagem_principal',
    'imagemUrl',
    'imageUrl',
    'fotoThumbUrl',
    'fotoOriginalUrl',
    'slug',
    'categoria',
    'categoriaId',
    'subcategoria',
    'subcategoriaId',
    'categoriasExtras',
    'subcategoriasExtras',
    'categoriasAssociadas',
    'subcategoriasAssociadas',
    'peso',
    'emPromocao',
    'percentualPromo',
    'valorPromo',
    'publicadoNoCatalogo',
    'exibir_no_catalogo',
    'ocultar_catalogo',
    'catalog_ativo',
    'priceMin',
    'priceMax',
    'images',
    'imgs',
    'fotos',
    'dataInicioPromo',
    'dataFimPromo',
    'precoComPromocao',
    'promocaoAtiva',
    'descontoComboValor',
    'descontoComboPercentual',
  };

  static Future<Map<String, dynamic>> saveEditorial(
    String lojaId,
    String productId,
    Map<String, dynamic> data,
  ) =>
      command(
        lojaId: lojaId,
        operationId: const Uuid().v4(),
        kind: 'editorial',
        items: [
          {'productId': _id(productId)}
        ],
        editorial: Map.fromEntries(
            data.entries.where((entry) => editorialFields.contains(entry.key))),
      );

  /// The caller allocates and persists operationId with its intent, before sending.
  /// Retries retain the same identity; identical new sales must have different IDs.
  ///
  /// [atomicPdvSale] opt-in: backend commits canonical estoque_vendas + stock
  /// in one transaction. Omit for old clients (stock-only + client syncVenda).
  static Future<Map<String, dynamic>> command({
    required String lojaId,
    required String operationId,
    required String kind,
    required List<Map<String, dynamic>> items,
    String? sourceOperationId,
    Map<String, dynamic>? editorial,
    Map<String, dynamic>? definition,
    List<String>? tombstoneKeys,
    bool atomicPdvSale = false,
    Map<String, dynamic>? sale,
  }) async {
    if (atomicPdvSale && sale == null) {
      throw ArgumentError('atomicPdvSale requires sale payload');
    }
    final rawPayload = <String, dynamic>{
      'protocolVersion': 1,
      'lojaId': _id(lojaId),
      'operationId': _id(operationId),
      'kind': kind,
      'items': items.map((item) => Map<String, dynamic>.from(item)).toList(),
      if (sourceOperationId != null)
        'sourceOperationId': _id(sourceOperationId),
      if (editorial != null) 'editorial': Map<String, dynamic>.from(editorial),
      if (definition != null)
        'definition': Map<String, dynamic>.from(definition),
      if (tombstoneKeys != null) 'tombstoneKeys': List<String>.from(tombstoneKeys),
      if (atomicPdvSale) 'atomicPdvSale': true,
      if (atomicPdvSale && sale != null)
        'sale': Map<String, dynamic>.from(sale),
    };
    final payload =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(rawPayload)) as Map);
    for (var attempt = 0;; attempt++) {
      try {
        return await _call('stockCatalogCommand', payload);
      } on FirebaseFunctionsException catch (error) {
        if (attempt >= 2 ||
            !{'unavailable', 'deadline-exceeded'}.contains(error.code)) {
          rethrow;
        }
        // No fallback to Firestore writes after an uncertain server commit.
      }
    }
  }
}
