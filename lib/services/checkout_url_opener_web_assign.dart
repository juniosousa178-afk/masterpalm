// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Same-tab: equivalente a `window.location.assign(url)`.
void assignCheckoutLocation(String url) {
  html.window.location.assign(url);
}
