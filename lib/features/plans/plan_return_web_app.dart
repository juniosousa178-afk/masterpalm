// App mínimo das páginas de retorno do checkout de planos (web).
// Não passa pelo bootstrap do app administrativo nem pelo roteamento de catálogo.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../web/platform_stub.dart'
    if (dart.library.html) '../../web/platform_web.dart' as plat;
import 'plan_return_link.dart';
import 'plan_return_screen.dart';

class PlanReturnWebApp extends StatelessWidget {
  const PlanReturnWebApp({
    super.key,
    required this.ref,
    required this.routeName,
    required this.loader,
    required this.onOpenApp,
    this.autoRefreshInterval = const Duration(seconds: 5),
  });

  final PlanReturnRef? ref;

  /// Path + query da URL aberta; o Navigator reporta esse nome ao browser
  /// (com `home:` reportaria `/` e o refresh perderia o retorno).
  final String routeName;
  final PlanReturnStatusLoader loader;
  final void Function(BuildContext context) onOpenApp;
  final Duration? autoRefreshInterval;

  Route<void> _route(String name) => MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => PlanReturnScreen(
          ref: ref,
          loader: loader,
          onOpenApp: onOpenApp,
          autoRefreshInterval: autoRefreshInterval,
        ),
      );

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      plat.Web.notifyCatalogHtmlLoaderReady('plan_return');
    });
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Assinatura MasterPalm',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      initialRoute: routeName,
      onGenerateInitialRoutes: (name) => [_route(name)],
      onGenerateRoute: (settings) => _route(settings.name ?? routeName),
    );
  }
}
