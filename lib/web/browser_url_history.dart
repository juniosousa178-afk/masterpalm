// Preservação da URL do browser no Flutter web (deep links, refresh, Voltar/Avançar).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Nome de rota que o Navigator raiz deve anunciar para a página aberta no browser.
///
/// Com `MaterialApp(home:)` o Navigator anuncia `/` e o engine troca a URL visível
/// do deep link por `/`; anunciando path + query + fragmento reais a URL fica intacta.
String browserRouteNameFor(Uri uri) {
  final name = StringBuffer(uri.path.isEmpty ? '/' : uri.path);
  if (uri.hasQuery) name.write('?${uri.query}');
  if (uri.hasFragment) name.write('#${uri.fragment}');
  return name.toString();
}

/// URL usada no lugar de `Uri.base` por [currentBrowserRouteName] em testes.
@visibleForTesting
Uri? debugBrowserUriOverride;

/// [browserRouteNameFor] da URL atual no web; `/` nas plataformas nativas.
String currentBrowserRouteName() {
  final uri = debugBrowserUriOverride ?? (kIsWeb ? Uri.base : null);
  return uri == null ? '/' : browserRouteNameFor(uri);
}

/// URL externa para a rota interna [internalUrl] do engine web.
///
/// O histórico de entrada única do Flutter marca a entrada de chegada ("origin")
/// com `replaceState(url: '')`, e o `PathUrlStrategy` converte `''` em `/`: depois
/// de Voltar, Avançar recarregava `/` em vez do deep link. `''` mantém a URL atual.
String landingPreservingExternalUrl(
  String internalUrl, {
  required String pathname,
  required String search,
  required String hash,
  required String Function(String internalUrl) fallback,
}) {
  if (internalUrl.isEmpty) return '$pathname$search$hash';
  return fallback(internalUrl);
}

/// Disponibiliza o `home` atual às rotas de [browserUrlHomeRoute], para que rebuilds
/// do app atualizem a tela como `MaterialApp(home:)` faria.
class BrowserUrlHome extends InheritedWidget {
  const BrowserUrlHome({super.key, required this.home, required super.child});

  final Widget home;

  static Widget of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrowserUrlHome>()!.home;

  @override
  bool updateShouldNotify(BrowserUrlHome oldWidget) =>
      !identical(home, oldWidget.home);
}

/// Rota raiz com nome [name] (a URL aberta) que mostra o `home` de [BrowserUrlHome].
Route<void> browserUrlHomeRoute(String name) => MaterialPageRoute<void>(
  settings: RouteSettings(name: name),
  builder: BrowserUrlHome.of,
);
