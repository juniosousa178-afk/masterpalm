// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import '../core/logger.dart';

/// Registra listener de [popstate] para correlacionar botão VOLTAR do navegador com [Uri.base].
void registerWebPopStateLogger() {
  html.window.onPopState.listen((html.PopStateEvent e) {
    logD(
      '[WEB_NAV] popstate state=${e.state} path=${html.window.location.pathname} href=${html.window.location.href}',
    );
  });
}
