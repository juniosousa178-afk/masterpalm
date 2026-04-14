// lib/services/deep_link_handler.dart
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import '../config/app_urls.dart';
import '../main.dart' show navigatorKey;

/// Handler de deep/app links que não depende de BuildContext.
class DeepLinkHandler {
  DeepLinkHandler._();
  static final DeepLinkHandler instance = DeepLinkHandler._();

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;
  Uri? _queuedInitial;

  /// Inicia captura de link inicial + stream. Idempotente.
  void init() {
    if (_initialized) return;
    _initialized = true;

    // Garante que só navega após existir um Navigator na árvore.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _handleInitial();
      _listenIncoming();
    });
  }

  Future<void> _handleInitial() async {
    try {
      _appLinks ??= AppLinks();
      final uri = await _appLinks!.getInitialLink();
      if (uri == null) return;
      debugPrint('🔗 [DeepLink] initial: $uri');
      _tryNavigate(uri);
    } catch (e) {
      debugPrint('⚠️ initial link error (type=${e.runtimeType})');
    }
  }

  void _listenIncoming() {
    _appLinks ??= AppLinks();
    _sub?.cancel();
    _sub = _appLinks!.uriLinkStream.listen(
      (uri) {
        debugPrint('🔗 [DeepLink] incoming: $uri');
        _tryNavigate(uri);
      },
      onError: (e, st) => debugPrint('⚠️ stream error (type=${e.runtimeType})'),
      cancelOnError: false,
    );
  }

  void _tryNavigate(Uri uri) {
    // empurra para o próximo frame: assegura Navigator conectado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        _queuedInitial = uri;
        _retry();
        return;
      }
      _routeFromUri(uri, nav);
      _queuedInitial = null;
    });
  }

  void _retry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uri = _queuedInitial;
      if (uri != null) _tryNavigate(uri);
    });
  }

  void _routeFromUri(Uri uri, NavigatorState nav) {
    try {
      // Suporta ?loja=<lojaId> e ?pedido=<pedidoId> como query params
      final lojaId = uri.queryParameters['loja'];
      final pedidoId = uri.queryParameters['pedido'];

      // HTTPS: App Web admin (hosts canônico + legado) e site público
      if (uri.scheme == 'https' &&
          (AppUrls.appWebHostsAll.contains(uri.host) ||
              AppUrls.publicSiteHostsAll.contains(uri.host))) {

        // Formato 1: /c/<slug>?pedido=<id>
        if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'c') {
          if (pedidoId != null && pedidoId.isNotEmpty) {
            final slug = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
            _openPedido(nav, pedidoId, lojaId: slug ?? lojaId);
            return;
          }
        }

        // Formato 2: /pedido/<id>
        if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'pedido') {
          final id = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
          if (id != null && id.isNotEmpty) {
            _openPedido(nav, id, lojaId: lojaId);
            return;
          }
        }
      }

      // Custom scheme: mastepalm://pedido/<id>
      if (uri.scheme == 'mastepalm' && uri.host == 'pedido') {
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        if (id != null && id.isNotEmpty) {
          _openPedido(nav, id, lojaId: lojaId);
          return;
        }
      }

      // Rotas de entrada normais (web App, /, /login) — não logar como "não reconhecida"
      final segments = uri.pathSegments;
      if (segments.isEmpty) return; // raiz do App Web
      final path = uri.path.toLowerCase().trim().replaceFirst(RegExp(r'/+$'), '').replaceFirst(RegExp(r'^/+'), '');
      if (path.isEmpty || path == 'login') return;

      debugPrint('ℹ️ [DeepLink] URI não reconhecida: $uri');
    } catch (e) {
      debugPrint('❌ routeFromUri error (type=${e.runtimeType})');
    }
  }

  void _openPedido(NavigatorState nav, String orderId, {String? lojaId}) {
    // Empurra argumentos para a rota nomeada. Sua onGenerateRoute deve recebê-los.
    nav.pushNamed(
      '/pedido/$orderId',
      arguments: <String, dynamic>{
        'orderId': orderId,
        if (lojaId != null && lojaId.isNotEmpty) 'lojaId': lojaId,
      },
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
