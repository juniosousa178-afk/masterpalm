import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_bootstrap_loading.dart';
import 'package:master_palm/catalog/public_order_link.dart';
import 'package:master_palm/screens/public_order_web_app.dart';
import 'package:master_palm/web/browser_url_history.dart';

List<String> _captureAnnouncedUrls(WidgetTester tester) {
  final announced = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
    if (call.method == 'routeInformationUpdated') {
      announced.add((call.arguments as Map)['uri'].toString());
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.navigation, null));
  return announced;
}

Future<void> _pumpHomeApp(
  WidgetTester tester, {
  required String routeName,
  required Widget home,
  Map<String, WidgetBuilder> routes = const {},
}) {
  return tester.pumpWidget(BrowserUrlHome(
    home: home,
    child: MaterialApp(
      routes: routes,
      initialRoute: routeName,
      onGenerateInitialRoutes: (name) => [browserUrlHomeRoute(name)],
      onGenerateRoute: (s) =>
          s.name == routeName ? browserUrlHomeRoute(routeName) : null,
    ),
  ));
}

void main() {
  tearDown(() => debugBrowserUriOverride = null);

  group('browserRouteNameFor', () {
    test('mantém path, query e fragmento do deep link', () {
      expect(
        browserRouteNameFor(Uri.parse('https://app.mastepalm.com.br/loja/minha-loja')),
        '/loja/minha-loja',
      );
      expect(
        browserRouteNameFor(
            Uri.parse('https://app.mastepalm.com.br/loja/x?cat=aneis&ord=preco')),
        '/loja/x?cat=aneis&ord=preco',
      );
      expect(
        browserRouteNameFor(Uri.parse('https://app.mastepalm.com.br/pedido/abc?loja=l1')),
        '/pedido/abc?loja=l1',
      );
      expect(
        browserRouteNameFor(Uri.parse('https://app.mastepalm.com.br/#/loja/x')),
        '/#/loja/x',
      );
    });

    test('raiz sem path vira /', () {
      expect(browserRouteNameFor(Uri.parse('https://app.mastepalm.com.br')), '/');
      expect(browserRouteNameFor(Uri.parse('https://app.mastepalm.com.br/?loja=x')),
          '/?loja=x');
    });

    test('preserva percent-encoding e sobrevive ao Uri.parse do engine', () {
      const href = 'https://app.mastepalm.com.br/loja/caf%C3%A9?q=a%20b&ref=v%2F1';
      final name = browserRouteNameFor(Uri.parse(href));
      expect(name, '/loja/caf%C3%A9?q=a%20b&ref=v%2F1');
      expect(Uri.parse(name).toString(), name);
    });

    test('currentBrowserRouteName usa a URL do browser ou / fora do web', () {
      expect(currentBrowserRouteName(), '/');
      debugBrowserUriOverride =
          Uri.parse('https://app.mastepalm.com.br/planos/retorno?status=approved');
      expect(currentBrowserRouteName(), '/planos/retorno?status=approved');
    });
  });

  group('landingPreservingExternalUrl', () {
    String pathStrategy(String internal) => internal.isEmpty ? '/' : internal;

    test('entrada "origin" (url vazia) mantém o deep link em vez de /', () {
      expect(pathStrategy(''), '/');
      expect(
        landingPreservingExternalUrl('',
            pathname: '/pedido/abc',
            search: '?loja=l1',
            hash: '',
            fallback: pathStrategy),
        '/pedido/abc?loja=l1',
      );
      expect(
        landingPreservingExternalUrl('',
            pathname: '/loja/x', search: '', hash: '#topo', fallback: pathStrategy),
        '/loja/x#topo',
      );
    });

    test('só a url vazia é tratada; rotas reais ficam idênticas ao PathUrlStrategy', () {
      const routes = [
        '/',
        '/home',
        '/login',
        '/loja/minha-loja',
        '/loja/minha-loja?cat=aneis&ord=preco',
        '/pedido/abc123?loja=minha-loja',
        '/assinatura/plano-pro/retorno',
        '/planos/retorno',
        '/planos/retorno?status=approved',
        '/assinatura/troca/chg_1/retorno',
      ];
      for (final route in routes) {
        expect(
          landingPreservingExternalUrl(route,
              pathname: '/outra/pagina',
              search: '?x=1',
              hash: '#y',
              fallback: pathStrategy),
          pathStrategy(route),
          reason: route,
        );
      }
    });

    test('rotas nomeadas seguem o PathUrlStrategy', () {
      final seen = <String>[];
      final out = landingPreservingExternalUrl('/home',
          pathname: '/loja/x',
          search: '',
          hash: '',
          fallback: (s) {
            seen.add(s);
            return pathStrategy(s);
          });
      expect(out, '/home');
      expect(seen, ['/home']);
    });
  });

  group('rota raiz anuncia a URL real (não /)', () {
    testWidgets('loja: deep link com query', (tester) async {
      final announced = _captureAnnouncedUrls(tester);
      await _pumpHomeApp(tester,
          routeName: '/loja/minha-loja?cat=aneis', home: const Text('catalogo'));
      expect(find.text('catalogo'), findsOneWidget);
      expect(announced, ['/loja/minha-loja?cat=aneis']);
    });

    testWidgets('rebuild troca o home sem anunciar nova rota', (tester) async {
      final announced = _captureAnnouncedUrls(tester);
      await _pumpHomeApp(tester, routeName: '/loja/x', home: const Text('v1'));
      await _pumpHomeApp(tester, routeName: '/loja/x', home: const Text('v2'));
      expect(find.text('v2'), findsOneWidget);
      expect(find.text('v1'), findsNothing);
      expect(announced, ['/loja/x']);
    });

    testWidgets('pushNamed(/home) continua funcionando e voltar não re-anuncia',
        (tester) async {
      final announced = _captureAnnouncedUrls(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(BrowserUrlHome(
        home: const Text('catalogo'),
        child: MaterialApp(
          navigatorKey: nav,
          routes: {'/home': (_) => const Text('home')},
          initialRoute: '/loja/x',
          onGenerateInitialRoutes: (name) => [browserUrlHomeRoute(name)],
          onGenerateRoute: (s) =>
              s.name == '/loja/x' ? browserUrlHomeRoute('/loja/x') : null,
        ),
      ));
      unawaited(nav.currentState!.pushNamed('/home'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('catalogo'), findsOneWidget);
      expect(announced, ['/loja/x', '/home', '/loja/x']);
    });

    testWidgets('CatalogBootstrapLoadingApp anuncia /loja/<slug>', (tester) async {
      debugBrowserUriOverride =
          Uri.parse('https://app.mastepalm.com.br/loja/minha-loja?cat=aneis');
      final announced = _captureAnnouncedUrls(tester);
      await tester.pumpWidget(const CatalogBootstrapLoadingApp(
        loadingContext: WebInitialLoadingContext.app,
      ));
      await tester.pumpWidget(const CatalogBootstrapLoadingApp(
        nomeLoja: 'Loja Teste',
        loadingContext: WebInitialLoadingContext.app,
      ));
      expect(find.text('Loja Teste'), findsOneWidget);
      expect(announced, ['/loja/minha-loja?cat=aneis']);
    });

    testWidgets('erro do bootstrap do catálogo mantém /loja/<slug>', (tester) async {
      debugBrowserUriOverride = Uri.parse('https://app.mastepalm.com.br/loja/minha-loja');
      final announced = _captureAnnouncedUrls(tester);
      await tester.pumpWidget(PublicCatalogBootstrapApp(
        firebaseSpanName: 'test.firebase',
        initFirebase: () async => false,
        afterFirebaseMinReady: ({required updateNomeLoja, required updateLogoUrl}) =>
            Future<void>.error(StateError('falha simulada')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(announced, isNotEmpty);
      expect(announced.toSet(), {'/loja/minha-loja'});
    });

    testWidgets('pedido público mantém /pedido/<id>?loja=<loja>', (tester) async {
      final announced = _captureAnnouncedUrls(tester);
      const route = '/pedido/abc123?loja=minha-loja';
      await tester.pumpWidget(PublicOrderWebApp(
        ref: PublicOrderLink.parse(Uri.parse('https://app.mastepalm.com.br$route')),
        routeName: route,
        initFirebase: () async => false,
      ));
      await tester.pumpAndSettle();
      expect(announced, [route]);
    });
  });
}
