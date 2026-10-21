// Web: URL sem hash, preservando o deep link na entrada de chegada do histórico.
import 'dart:ui_web' as ui_web;

// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';

import 'web/browser_url_history.dart';

void usePathUrlStrategy() => setUrlStrategy(LandingPreservingPathUrlStrategy());

/// [PathUrlStrategy] que não reescreve a entrada "origin" do histórico para `/`.
/// Ver [landingPreservingExternalUrl].
class LandingPreservingPathUrlStrategy extends PathUrlStrategy {
  static const ui_web.BrowserPlatformLocation _location =
      ui_web.BrowserPlatformLocation();

  @override
  String prepareExternalUrl(String internalUrl) => landingPreservingExternalUrl(
        internalUrl,
        pathname: _location.pathname,
        search: _location.search,
        hash: _location.hash,
        fallback: super.prepareExternalUrl,
      );
}
