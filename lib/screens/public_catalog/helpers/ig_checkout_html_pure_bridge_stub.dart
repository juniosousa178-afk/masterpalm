// Stub (mobile / analyzer): sem dart:html.

import 'dart:async';

/// Bridge mínimo para checkout HTML → Flutter (Instagram WebView).
class IgCheckoutHtmlPureBridge {
  IgCheckoutHtmlPureBridge._();

  static String? locationHref() => null;

  static Uri currentUri() => Uri.parse('about:blank');

  static StreamSubscription<dynamic> listenPopState(void Function() onPop) {
    return const Stream<void>.empty().listen(null);
  }

  static void igCheckoutHistoryReplaceState(Uri newUri) {}

  static String? localStorageGet(String key) => null;

  static void localStorageRemove(String key) {}
}
