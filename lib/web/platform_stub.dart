// lib/web/platform_stub.dart
// Stub para plataformas NÃO-Web (e também para o analyzer).
// NÃO importe dart:html aqui.

import 'dart:async';

// Tipo público para evitar "library_private_types_in_public_api"
class LocationStub {
  String href = '';
}

/// Versão mínima para compilar fora do Web.
/// Fornece .close() e .location.href usados no código Web.
class HtmlWindowBase {
  void close() {}
  final LocationStub location = LocationStub();
}

class Web {
  static bool isIosWebKit() => false;
  static String userAgent() => '';

  static bool catalogLikelyEmbeddedSocialBrowser() => false;

  static bool isInstagramAndroidWebView() => false;

  static Map<String, dynamic> catalogViewportMetrics() => <String, dynamic>{};

  static void applyCatalogIgAndroidDomGuards() {}

  static void consoleLog(String message) {}

  static StreamSubscription<void>? listenVisualViewportResize(
    void Function() onResize,
  ) =>
      null;

  // DOM/Janela (no-ops)
  static void scrollToTop() {}
  static void addPopState(void Function(dynamic) h) {}

  static HtmlWindowBase? open(String url, String name) => null;
  static String locationHref() => '';
  static void setLocationHash(String hash) {}
  static void setTitle(String t) {}

  // Armazenamento local (vazio no stub)
  static Map<String, String> get localStorage => <String, String>{};
  static void localStorageSet(String key, String value) {}
  static String? localStorageGet(String key) => null;

  static void setMetaThemeColor(String hex) {}

  static String? querySelectorContent(String selector) => null;

  static void setLinkHref(String selector, String href) {}

  // JS bridge (no-op)
  static dynamic callJs(String fn, List args) => null;

  // Helpers
  static bool hasElById(String id) => false;

  static Future<void> loadScript({
    required String id,
    required String src,
    bool defer = true,
  }) async {}

  static Future<String> httpPostJson(String url, String jsonBody) async => '{}';

  /// Navega na janela previamente aberta (no-op no stub)
  static void navigateInOpened(HtmlWindowBase? win, String url) {}

  /// Remove o loader estático de [web/index.html] após o primeiro frame Flutter.
  static void hideInitialCatalogLoader() {}

  /// Só Web: origem de `main.dart.js` e estado de SW/Cache (netTest / diagnóstico).
  static String? getMainDartJsScriptSrc() => null;

  static Future<Map<String, dynamic>> netTestBuildProvenance() async =>
      <String, dynamic>{};
}
