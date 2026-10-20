// App mínimo da página pública do pedido (web `/pedido/{pedidoId}?loja={lojaId}`).
// Não passa pelo bootstrap do app administrativo: o cliente nunca precisa de login de lojista.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../catalog/public_order_link.dart';
import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as plat;
import 'pedido_publico_screen.dart';

class PublicOrderWebApp extends StatefulWidget {
  const PublicOrderWebApp({
    super.key,
    required this.ref,
    required this.routeName,
    required this.initFirebase,
  });

  /// `null` quando a URL tem path `/pedido/...` mas a referência é inválida.
  final PublicOrderRef? ref;

  /// Path + query da URL aberta; o Navigator reporta esse nome ao browser
  /// (com `home:` reportaria `/` e o refresh perderia o pedido).
  final String routeName;
  final Future<bool> Function() initFirebase;

  @override
  State<PublicOrderWebApp> createState() => _PublicOrderWebAppState();
}

class _PublicOrderWebAppState extends State<PublicOrderWebApp> {
  late final Future<bool> _ready;

  @override
  void initState() {
    super.initState();
    _ready = widget.ref == null
        ? Future<bool>.value(true)
        : widget.initFirebase().catchError((_) => false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      plat.Web.notifyCatalogHtmlLoaderReady('public_order');
    });
  }

  Route<void> _route(String name) => MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => _body(),
      );

  Widget _body() {
    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snap) {
        final ref = widget.ref;
        if (ref == null) {
          return const PedidoPublicoErroScaffold(
            mensagem: PedidoPublicoScreen.mensagemLinkInvalido,
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != true) {
          return const PedidoPublicoErroScaffold(
            mensagem: PedidoPublicoScreen.mensagemFalhaCarregamento,
          );
        }
        return PedidoPublicoScreen(
          lojaId: ref.lojaId,
          prePedidoId: ref.pedidoId,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pedido',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      initialRoute: widget.routeName,
      onGenerateInitialRoutes: (name) => [_route(name)],
      onGenerateRoute: (settings) => _route(settings.name ?? widget.routeName),
    );
  }
}
