// lib/web/platform_web.dart
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

export 'dart:html' show WindowBase;

/// Alias com UpperCamelCase (conserta o warning de naming)
typedef HtmlWindowBase = html.WindowBase;

/// Compila só no Web.
class Web {
  static bool isIosWebKit() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    final isAppleMobile =
        ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
    final isWebKit = ua.contains('applewebkit');
    return isAppleMobile && isWebKit;
  }

  static String userAgent() => html.window.navigator.userAgent;

  /// Navegador embutido de redes sociais (Instagram, Facebook/Messenger IAB, etc.).
  /// No Flutter Web, `showModalBottomSheet` + teclado costuma falhar nesses WebViews.
  static bool catalogLikelyEmbeddedSocialBrowser() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (ua.contains('instagram')) return true;
    if (ua.contains('fban') || ua.contains('fbav')) return true;
    if (ua.contains('fb_iab') || ua.contains('fbiab')) return true;
    if (ua.contains(' line/')) return true;
    if (ua.contains('tiktok')) return true;
    return false;
  }

  /// Instagram in-app browser no Android (link da bio). Exclui iPhone/iPad.
  static bool isInstagramAndroidWebView() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (!ua.contains('instagram')) return false;
    if (ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod')) {
      return false;
    }
    return ua.contains('android');
  }

  /// Métricas de viewport para diagnóstico de layout (sem dados pessoais).
  static Map<String, dynamic> catalogViewportMetrics() {
    final w = html.window;
    final doc = html.document.documentElement;
    double? vvW;
    double? vvH;
    try {
      final vv = w.visualViewport;
      if (vv != null) {
        vvW = vv.width?.toDouble();
        vvH = vv.height?.toDouble();
      }
    } catch (_) {}
    return <String, dynamic>{
      'innerWidth': w.innerWidth,
      'innerHeight': w.innerHeight,
      'clientWidth': doc?.client.width,
      'clientHeight': doc?.client.height,
      'devicePixelRatio': w.devicePixelRatio,
      'visualViewportWidth': vvW,
      'visualViewportHeight': vvH,
    };
  }

  /// Evita faixa lateral por overflow horizontal no host Flutter (IG Android).
  static void applyCatalogIgAndroidDomGuards() {
    try {
      const styleId = 'mp-ig-android-catalog-guards';
      if (html.document.getElementById(styleId) != null) {
        html.document.body?.classes.add('mp-ig-android-webview');
        return;
      }
      final style = html.StyleElement()
        ..id = styleId
        ..text = '''
html, body {
  overflow-x: hidden !important;
  width: 100% !important;
  max-width: 100% !important;
  margin: 0;
  padding: 0;
  position: relative;
}
body.mp-ig-android-webview {
  overflow-x: hidden !important;
  overscroll-behavior-x: none;
}
flt-glass-pane, flutter-view, #flutter-view {
  width: 100% !important;
  max-width: 100% !important;
  overflow-x: hidden !important;
  box-sizing: border-box !important;
}
''';
      html.document.head?.append(style);
      html.document.body?.classes.add('mp-ig-android-webview');
    } catch (_) {}
  }

  static void consoleLog(String message) {
    try {
      // ignore: avoid_print
      html.window.console.log(message);
    } catch (_) {}
  }

  static StreamSubscription<void>? listenVisualViewportResize(
    void Function() onResize,
  ) {
    try {
      final vv = html.window.visualViewport;
      if (vv == null) return null;
      return vv.onResize.listen((_) => onResize());
    } catch (_) {
      return null;
    }
  }

  // DOM/Janela
  static void scrollToTop() => html.window.scrollTo(0, 0);

  static void addPopState(void Function(html.PopStateEvent) h) =>
      html.window.onPopState.listen(h);

  static HtmlWindowBase? open(String url, String name) =>
      html.window.open(url, name);

  static String locationHref() => html.window.location.href;

  static void setLocationHash(String hash) => html.window.location.hash = hash;

  static void setTitle(String t) => html.document.title = t;

  /// Acesso ao localStorage (usado no _detectSlug)
  static Map<String, String> get localStorage => html.window.localStorage;

  static void localStorageSet(String key, String value) {
    try {
      html.window.localStorage[key] = value;
    } catch (_) {}
  }

  static String? localStorageGet(String key) {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  static void setMetaThemeColor(String hex) {
    final el = html.document.querySelector('meta[name="theme-color"]')
        as html.MetaElement?;
    if (el != null) el.content = hex;
  }

  static String? querySelectorContent(String selector) {
    final el = html.document.querySelector(selector);
    if (el is html.MetaElement) return el.content;
    if (el is html.LinkElement) return el.href;
    return null;
  }

  static void setLinkHref(String selector, String href) {
    final el = html.document.querySelector(selector);
    if (el is html.LinkElement) el.href = href;
  }

  // JS bridge
  static dynamic callJs(String fn, List args) {
    return js.context.callMethod(fn, args);
  }

  // Helpers
  static bool hasElById(String id) => html.document.getElementById(id) != null;

  static Future<void> loadScript({
    required String id,
    required String src,
    bool defer = true,
  }) async {
    final script = html.ScriptElement()
      ..id = id
      ..defer = defer
      ..src = src;

    final c = Completer<void>();
    script.onLoad.listen((_) => c.complete());
    script.onError.listen((_) => c.completeError('Falha ao carregar $src'));

    html.document.body!.append(script);
    await c.future;
  }

  static Future<String> httpPostJson(String url, String jsonBody) async {
    final resp = await html.HttpRequest.request(
      url,
      method: 'POST',
      sendData: jsonBody,
      requestHeaders: {'Content-Type': 'application/json'},
    );
    return resp.responseText ?? '{}';
  }

  /// Navega na janela previamente aberta (evita bloqueio de pop-up).
  static void navigateInOpened(HtmlWindowBase? win, String url) {
    try {
      if (win != null) {
        win.location.href = url;
        return;
      }
    } catch (_) {
      // se der erro, cai no open abaixo
    }
    html.window.open(url, '_blank');
  }

  /// Remove o overlay `#initial-loader` de [web/index.html] (backup do evento `flutter-first-frame`).
  static void hideInitialCatalogLoader() {
    try {
      html.document.getElementById('initial-loader')?.remove();
    } catch (_) {}
  }

  static String? getMainDartJsScriptSrc() {
    try {
      for (final n in html.document.querySelectorAll('script')) {
        if (n is! html.ScriptElement) continue;
        final src = n.src;
        if (src.isNotEmpty && src.contains('main.dart.js')) {
          return src;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>> netTestBuildProvenance() async {
    final out = <String, dynamic>{
      'mainDartJsScriptSrc': getMainDartJsScriptSrc(),
    };
    try {
      final sw = html.window.navigator.serviceWorker;
      if (sw != null) {
        final c = sw.controller;
        out['serviceWorkerController'] = c?.scriptUrl;
        out['serviceWorkerControllerIsNull'] = c == null;
      } else {
        out['serviceWorker'] = 'unavailable';
      }
    } catch (e) {
      out['serviceWorkerError'] = e.toString();
    }
    try {
      final cs = html.window.caches;
      if (cs != null) {
        out['caches'] = await cs.keys();
      } else {
        out['caches'] = <String>[];
        out['cacheStorage'] = 'unavailable';
      }
    } catch (e) {
      out['cachesError'] = e.toString();
    }
    return out;
  }
}
