// Diagnóstico M2.3 — rastreio de identidade no add-to-cart (apenas debug/test).
// Em release os listeners não são invocados.

import 'package:flutter/foundation.dart';

/// Evento de uma etapa do fluxo carrinho/catálogo.
class CatalogCartIdentityTraceEvent {
  const CatalogCartIdentityTraceEvent({
    required this.traceId,
    required this.stage,
    this.eventSequence,
    this.sourcePath,
    this.route,
    this.routeIdentity,
    this.widgetRuntimeType,
    this.widgetKey,
    this.stateIdentity,
    this.mounted,
    this.cartLineKey,
    this.productId,
    this.nome,
    this.preco,
    this.precoPix,
    this.tamanho,
    this.cor,
    this.extra,
    this.imagem,
    this.widgetLabel,
    this.timestamp,
    this.extraFields = const {},
  });

  final String traceId;
  final String stage;
  final int? eventSequence;
  final String? sourcePath;
  final String? route;
  final String? routeIdentity;
  final String? widgetRuntimeType;
  final String? widgetKey;
  final String? stateIdentity;
  final bool? mounted;
  final String? cartLineKey;
  final String? productId;
  final String? nome;
  final double? preco;
  final double? precoPix;
  final String? tamanho;
  final String? cor;
  final String? extra;
  final String? imagem;
  final String? widgetLabel;
  final DateTime? timestamp;
  final Map<String, String> extraFields;

  Map<String, dynamic> toJson() => {
        'traceId': traceId,
        'stage': stage,
        if (eventSequence != null) 'eventSequence': eventSequence,
        if (sourcePath != null && sourcePath!.isNotEmpty) 'sourcePath': sourcePath,
        if (route != null) 'route': route,
        if (routeIdentity != null) 'routeIdentity': routeIdentity,
        if (widgetRuntimeType != null) 'widgetRuntimeType': widgetRuntimeType,
        if (widgetKey != null) 'widgetKey': widgetKey,
        if (stateIdentity != null) 'stateIdentity': stateIdentity,
        if (mounted != null) 'mounted': mounted,
        if (cartLineKey != null) 'cartLineKey': cartLineKey,
        if (productId != null) 'productId': productId,
        if (nome != null) 'nome': nome,
        if (preco != null) 'preco': preco,
        if (precoPix != null) 'precoPix': precoPix,
        if (tamanho != null) 'tamanho': tamanho,
        if (cor != null) 'cor': cor,
        if (extra != null) 'extra': extra,
        if (imagem != null) 'imagem': imagem,
        if (widgetLabel != null) 'widgetLabel': widgetLabel,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
        if (extraFields.isNotEmpty) 'extraFields': extraFields,
      };
}

final List<void Function(CatalogCartIdentityTraceEvent)> _listeners = [];
int _catalogCartIdentityTraceSequence = 0;

@visibleForTesting
void catalogCartIdentityTraceReset() {
  _listeners.clear();
  _catalogCartIdentityTraceSequence = 0;
}

@visibleForTesting
void catalogCartIdentityTraceSubscribe(
  void Function(CatalogCartIdentityTraceEvent event) listener,
) {
  _listeners.add(listener);
}

/// Identificador de trace para instrumentação debug/test (uso em produção permitido).
String catalogCartIdentityNewTraceId() =>
    'tr-${DateTime.now().microsecondsSinceEpoch}';

/// Emite evento somente em debug/profile.
void catalogCartIdentityTrace(CatalogCartIdentityTraceEvent event) {
  final enriched = event.eventSequence == null
      ? CatalogCartIdentityTraceEvent(
          traceId: event.traceId,
          stage: event.stage,
          eventSequence: ++_catalogCartIdentityTraceSequence,
          sourcePath: event.sourcePath,
          route: event.route,
          routeIdentity: event.routeIdentity,
          widgetRuntimeType: event.widgetRuntimeType,
          widgetKey: event.widgetKey,
          stateIdentity: event.stateIdentity,
          mounted: event.mounted,
          cartLineKey: event.cartLineKey,
          productId: event.productId,
          nome: event.nome,
          preco: event.preco,
          precoPix: event.precoPix,
          tamanho: event.tamanho,
          cor: event.cor,
          extra: event.extra,
          imagem: event.imagem,
          widgetLabel: event.widgetLabel,
          timestamp: event.timestamp ?? DateTime.now().toUtc(),
          extraFields: event.extraFields,
        )
      : event;
  assert(() {
    for (final listener in _listeners) {
      listener(enriched);
    }
    return true;
  }());
  if (kDebugMode && _listeners.isNotEmpty) {
    for (final listener in _listeners) {
      listener(enriched);
    }
  }
}
