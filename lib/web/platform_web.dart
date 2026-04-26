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
}
