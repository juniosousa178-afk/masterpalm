import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/sale_forensic_trace.dart';
import '../diagnostics/diagnostic_enums.dart';
import '../diagnostics/diagnostic_trace_service.dart';

/// Structured multi-product validation failure from stockCatalogCommand.
class StockCatalogProductValidationException implements Exception {
  StockCatalogProductValidationException(this.message, {this.issues = const []});

  final String message;
  final List<Map<String, dynamic>> issues;

  @override
  String toString() => message;

  static StockCatalogProductValidationException? tryParse(
      FirebaseFunctionsException error) {
    final details = error.details;
    if (details is! Map) return null;
    final code = '${details['code'] ?? error.message ?? ''}'.trim();
    if (code != 'PRODUCT_VALIDATION_FAILED') return null;
    final raw = details['issues'];
    final issues = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) issues.add(Map<String, dynamic>.from(item));
      }
    }
    if (issues.isEmpty) {
      return StockCatalogProductValidationException(
        'Não foi possível concluir. Verifique os produtos selecionados.',
      );
    }
    final buffer = StringBuffer('Não foi possível concluir a operação.\n\n');
    buffer.writeln(
        '${issues.length} produto${issues.length == 1 ? '' : 's'} precisam de atenção:');
    for (final issue in issues) {
      final name = '${issue['productName'] ?? issue['productId'] ?? ''}';
      final selection = '${issue['selectionLabel'] ?? ''}'.trim();
      final label =
          selection.isEmpty ? name : '$name ($selection)';
      final msg = '${issue['userMessage'] ?? 'Este produto não pode ser usado nesta operação.'}';
      buffer.writeln('• $label — $msg');
    }
    return StockCatalogProductValidationException(
      buffer.toString().trim(),
      issues: issues,
    );
  }
}

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
      publishAllResumable(lojaId);

  /// Chunked/resumable catalog publish. Progress callback: (done, totalPublishable).
  static Future<Map<String, dynamic>> publishAllResumable(
    String lojaId, {
    int chunkSize = 75,
    void Function(int done, int total)? onProgress,
  }) async {
    final id = _id(lojaId);
    // PREPARE — classify once (no stock writes).
    final prepare = await _call('catalogPublishAll', {
      'lojaId': id,
      'prepareOnly': true,
    });
    final publishable = (prepare['publishableIds'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final blockers = List<dynamic>.from(prepare['blockers'] as List? ?? const []);
    final total = publishable.length;
    onProgress?.call(0, total);

    final completed = <String>[];
    var remaining = List<String>.from(publishable);
    Map<String, dynamic> last = Map<String, dynamic>.from(prepare);

    while (remaining.isNotEmpty) {
      try {
        last = await _call('catalogPublishAll', {
          'lojaId': id,
          'chunkSize': chunkSize,
          'productIds': remaining.take(chunkSize).toList(),
          'completedIds': const <String>[],
        });
      } on FirebaseFunctionsException catch (e) {
        // Transport timeout/internal: preserve completed work for resume.
        if (const {'deadline-exceeded', 'internal', 'unavailable'}
            .contains(e.code)) {
          return {
            ...last,
            'outcome': completed.isEmpty ? 'FAILED' : 'SUCCESS_WITH_BLOCKERS',
            'PUBLISHED': completed.length,
            'completedIds': completed,
            'remainingIds': remaining,
            'blockers': blockers,
            'transportError': e.code,
            'CATALOG_PUBLISH_RESUMABLE': true,
            'resumeFromCompletedIds': completed,
          };
        }
        rethrow;
      }

      final chunkDone = (last['completedIds'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      for (final pid in chunkDone) {
        if (!completed.contains(pid)) completed.add(pid);
      }
      final newBlockers = last['blockers'] as List? ?? const [];
      for (final b in newBlockers) {
        if (!blockers.any((x) =>
            x is Map &&
            b is Map &&
            '${x['productId']}' == '${b['productId']}')) {
          blockers.add(b);
        }
      }
      remaining = remaining.where((p) => !completed.contains(p)).toList();
      // Skip runtime-blocked from this chunk.
      for (final b in newBlockers) {
        if (b is Map) {
          final pid = '${b['productId']}';
          remaining.remove(pid);
        }
      }
      if (last['failedId'] != null) {
        remaining.remove('${last['failedId']}');
      }
      onProgress?.call(completed.length, total);
      if (last['outcome'] == 'FAILED' && remaining.isEmpty) break;
    }

    final outcome = (last['FAILED_UNEXPECTED'] ?? 0) > 0
        ? 'FAILED'
        : (blockers.isNotEmpty ? 'SUCCESS_WITH_BLOCKERS' : 'SUCCESS');

    return {
      ...last,
      'outcome': outcome,
      'TOTAL': prepare['TOTAL'] ?? total,
      'PUBLISHED': completed.length,
      'SKIPPED_BLOCKED': blockers.length,
      'completedIds': completed,
      'remainingIds': remaining,
      'blockers': blockers,
      'CATALOG_PUBLISH_RESUMABLE': true,
    };
  }
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
    // Per-product commercial terms (not store checkout maxParcelas/jurosParcelamento).
    'divideSemJuros',
    'percentualDescontoPix',
    'maxParcelasSemJuros',
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
  static Future<Map<String, dynamic>> command({
    required String lojaId,
    required String operationId,
    required String kind,
    required List<Map<String, dynamic>> items,
    String? sourceOperationId,
    Map<String, dynamic>? editorial,
    Map<String, dynamic>? definition,
    List<String>? tombstoneKeys,
    Map<String, dynamic>? reconciliation,
  }) async {
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
      if (reconciliation != null)
        'reconciliation': Map<String, dynamic>.from(reconciliation),
    };
    final payload =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(rawPayload)) as Map);
    // Observability only — does not alter command semantics.
    if (kind == 'sale' && SaleForensicTraceStore.active != null) {
      SaleForensicTraceStore.captureSalePayload(
        storeId: lojaId,
        operationId: operationId,
        items: items,
      );
    }
    final diagModule = switch (kind) {
      'sale' => DiagnosticModule.sales,
      'restore' => DiagnosticModule.restore,
      'replace' ||
      'adjust' ||
      'create' ||
      'editorial' ||
      'physicalReconciliation' =>
        DiagnosticModule.stock,
      _ => DiagnosticModule.cloudFunction,
    };
    final hadActiveDiag = DiagnosticTraceService.activeTraceId != null;
    if (!hadActiveDiag) {
      DiagnosticTraceService.start(
        storeId: lojaId,
        module: diagModule,
        operationType: kind,
        extra: {'operationId': operationId},
      );
    }
    DiagnosticTraceService.stage(
      DiagnosticStages.stockCommandStart,
      extra: {'kind': kind, 'operationId': operationId},
    );
    for (var attempt = 0;; attempt++) {
      try {
        final result = await _call('stockCatalogCommand', payload);
        final already = result['alreadyApplied'] == true;
        DiagnosticTraceService.success(
          already
              ? DiagnosticStages.stockCommandAlreadyApplied
              : DiagnosticStages.stockCommandSuccess,
          extra: {'kind': kind, 'operationId': operationId},
        );
        if (kind == 'sale' && SaleForensicTraceStore.active != null) {
          SaleForensicTraceStore.captureSaleCommandSuccess(result);
        }
        if (!hadActiveDiag) {
          DiagnosticTraceService.complete();
        }
        return result;
      } on FirebaseFunctionsException catch (error, st) {
        DiagnosticTraceService.error(
          DiagnosticStages.stockCommandStart,
          error,
          stack: st,
          extra: {'kind': kind, 'code': error.code},
        );
        if (kind == 'sale' && SaleForensicTraceStore.active != null) {
          SaleForensicTraceStore.captureRawCallableError(
            error: error,
            stack: st,
            errorCaughtAt: 'stockCatalogCommand.call',
          );
        }
        final validation = StockCatalogProductValidationException.tryParse(error);
        if (validation != null) {
          if (!hadActiveDiag) {
            DiagnosticTraceService.complete(aborted: true);
          }
          throw validation;
        }
        if (attempt >= 2 ||
            !{'unavailable', 'deadline-exceeded'}.contains(error.code)) {
          if (!hadActiveDiag) {
            DiagnosticTraceService.complete(aborted: true);
          }
          rethrow;
        }
        // No fallback to Firestore writes after an uncertain server commit.
      }
    }
  }
}
