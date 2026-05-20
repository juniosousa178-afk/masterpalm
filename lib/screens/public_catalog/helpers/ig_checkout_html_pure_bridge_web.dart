// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

/// Bridge Web: localStorage + history para retorno do checkout HTML (Instagram).
class IgCheckoutHtmlPureBridge {
  IgCheckoutHtmlPureBridge._();

  static String? locationHref() {
    try {
      return html.window.location.href;
    } catch (_) {
      return null;
    }
  }

  static Uri currentUri() {
    try {
      return Uri.parse(html.window.location.href);
    } catch (_) {
      return Uri.base;
    }
  }

  static StreamSubscription<dynamic> listenPopState(void Function() onPop) {
    return html.window.onPopState.listen((_) => onPop());
  }

  static void igCheckoutHistoryReplaceState(Uri newUri) {
    try {
      html.window.history.replaceState(null, '', newUri.toString());
    } catch (_) {}
  }

  static String? localStorageGet(String key) {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  static void localStorageRemove(String key) {
    try {
      html.window.localStorage.remove(key);
    } catch (_) {}
  }
}
