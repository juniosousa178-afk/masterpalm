// Catálogo público Web: primeira pintura com loader (evita tela branca).
//
// Catálogo público não deve passar pelo bootstrap pesado do app (Hive, sessão, RemoteConfig)
// antes do primeiro frame. Isso causa tela branca e atraso.
//
// Não depende de lojaId, config nem produtos — só tema + texto.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../debug/bootstrap_diagnostics.dart';
import '../debug/catalog_startup_trace.dart';
import '../screens/public_catalog/widgets/catalog_unified_loading.dart';
import '../themes/app_colors.dart';
import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as plat;

const String kCatalogDiagBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'dev',
);

/// Textos do primeiro loader Web: app administrativo vs vitrine pública.
enum WebInitialLoadingContext {
  /// SPA gestão / admin (host canónico, fora de `/loja/…`).
  app,

  /// Catálogo público (`/loja/…`, query legada ou domínio da loja).
  catalog,
}

/// Tela leve exibida antes de resolver domínio / Firebase mínimo.
class CatalogBootstrapLoadingScreen extends StatelessWidget {
  const CatalogBootstrapLoadingScreen({
    super.key,
    this.nomeLoja,
    this.logoUrl,
    this.loadingContext = WebInitialLoadingContext.catalog,
  });

  final String? nomeLoja;
  final String? logoUrl;

  /// [catalog] — textos da vitrine; [app] — gestão MasterPalm Web.
  final WebInitialLoadingContext loadingContext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nomeLojaSafe = (nomeLoja ?? '').trim();
    final logo = (logoUrl ?? '').trim();
    final hasLogo = logo.isNotEmpty;

    final String tituloPill;
    final String tituloCentral;
    final String frase;
    switch (loadingContext) {
      case WebInitialLoadingContext.app:
        tituloPill = nomeLojaSafe.isNotEmpty ? nomeLojaSafe : 'MasterPalm';
        tituloCentral = 'Aguarde';
        frase =
            'Estamos preparando sua experiência MasterPalm. Em instantes, você verá tudo pronto para vender mais.';
        break;
      case WebInitialLoadingContext.catalog:
        if (kIsWeb) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: SizedBox.shrink(),
          );
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF0F2F5),
          body: SafeArea(
            child: CatalogUnifiedLoadingView(
              nomeLoja: nomeLoja,
              logoUrl: logoUrl,
              diagPhaseLabel: 'bootstrap_firebase',
            ),
          ),
        );
    }

    Widget fallbackPill() {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF9A4E6B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          tituloPill,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasLogo)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 72,
                        maxWidth: 220,
                      ),
                      child: Image.network(
                        logo,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => fallbackPill(),
                      ),
                    )
                  else
                    fallbackPill(),
                  const SizedBox(height: 36),
                  Text(
                    tituloCentral,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    frase,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alias documental (mesmo widget que [CatalogBootstrapLoadingScreen]).
typedef PublicCatalogInitialLoadingScreen = CatalogBootstrapLoadingScreen;

/// `MaterialApp` mínimo só com o loader (primeiro `runApp` no fast path).
class CatalogBootstrapLoadingApp extends StatelessWidget {
  const CatalogBootstrapLoadingApp({
    super.key,
    this.nomeLoja,
    this.logoUrl,
    this.loadingContext = WebInitialLoadingContext.catalog,
  });

  final String? nomeLoja;
  final String? logoUrl;
  final WebInitialLoadingContext loadingContext;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      ),
      home: CatalogBootstrapLoadingScreen(
        nomeLoja: nomeLoja,
        logoUrl: logoUrl,
        loadingContext: loadingContext,
      ),
    );
  }
}

/// Primeiro `runApp` no catálogo público Web: loader imediato → Firebase mínimo → [afterFirebaseMinReady]
/// (ex.: resolver domínio e `runApp`([CatalogWebRoot])).
///
/// **Não** chama `_bootstrapSafe`, Hive, RemoteConfig nem AppCheck — isso fica só para o app administrativo.
class PublicCatalogBootstrapApp extends StatefulWidget {
  const PublicCatalogBootstrapApp({
    super.key,
    required this.initFirebase,
    required this.afterFirebaseMinReady,
    required this.firebaseSpanName,
    this.initialNomeLoja,
    this.initialLogoUrl,
  });

  final Future<bool> Function() initFirebase;
  final Future<void> Function({
    required void Function(String? nomeLoja) updateNomeLoja,
    required void Function(String? logoUrl) updateLogoUrl,
  }) afterFirebaseMinReady;
  final String? initialNomeLoja;
  final String? initialLogoUrl;

  /// Ex.: `CAT_START.fast_path.firebase_min_init` ou `CAT_START.custom_domain.fast_path.firebase`
  final String firebaseSpanName;

  @override
  State<PublicCatalogBootstrapApp> createState() =>
      _PublicCatalogBootstrapAppState();
}

class _PublicCatalogBootstrapAppState extends State<PublicCatalogBootstrapApp> {
  late String? _nomeLoja;
  late String? _logoUrl;
  String? _bootstrapErrorMessage;
  String? _bootstrapTechnicalMessage;
  String? _bootstrapStack;
  bool _bootstrapRunning = false;
  bool _bootstrapHtmlHandoffDone = false;

  void _scheduleHtmlLoaderHandoff(String reason) {
    if (!kIsWeb || _bootstrapHtmlHandoffDone) return;
    _bootstrapHtmlHandoffDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      plat.Web.notifyCatalogHtmlLoaderReady(reason);
    });
  }

  void _updateNomeLoja(String? nomeLoja) {
    if (!mounted) return;
    setState(() {
      _nomeLoja = nomeLoja;
    });
  }

  void _updateLogoUrl(String? logoUrl) {
    if (!mounted) return;
    setState(() {
      _logoUrl = logoUrl;
    });
  }

  @override
  void initState() {
    super.initState();
    _nomeLoja = widget.initialNomeLoja;
    _logoUrl = widget.initialLogoUrl;
    if (kDebugMode) {
      debugPrint('[CATALOG_BOOT] first_frame_loader');
    }
    _startBootstrap();
  }

  void _startBootstrap() {
    if (_bootstrapRunning) return;
    _bootstrapErrorMessage = null;
    _bootstrapTechnicalMessage = null;
    _bootstrapStack = null;
    _bootstrapRunning = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    if (kIsWeb) {
      plat.Web.localStorageSet('mp_catalog_phase', 'catalog.loja.load.start');
    }
    CatalogStartupTrace.spanStart(widget.firebaseSpanName);
    var firebaseOk = false;
    try {
      if (kDebugMode) debugPrint('[CATALOG_BOOT] firebase.min.begin');
      firebaseOk = await widget.initFirebase().timeout(
            const Duration(seconds: 20),
            onTimeout: () => false,
          );
      if (kDebugMode) {
        debugPrint(
          '[CATALOG_BOOT] firebase.min.${firebaseOk ? 'ok' : 'fail'}',
        );
      }
      if (firebaseOk) {
        FirebaseGuard.markReady();
      }
      if (kIsWeb) {
        plat.Web.localStorageSet('mp_catalog_phase', 'catalog.loja.load.done');
      }
      CatalogStartupTrace.spanEnd(
        widget.firebaseSpanName,
        data: {'ok': firebaseOk},
      );
    } catch (e) {
      CatalogStartupTrace.spanEnd(
        widget.firebaseSpanName,
        data: {'ok': false, 'error_type': e.runtimeType.toString()},
      );
      logW(
        '⚠️ [CATALOG_BOOT] initFirebase falhou (type=${e.runtimeType})',
      );
    }

    try {
      await widget
          .afterFirebaseMinReady(
        updateNomeLoja: _updateNomeLoja,
        updateLogoUrl: _updateLogoUrl,
      )
          .timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw TimeoutException('afterFirebaseMinReady timeout');
        },
      );
    } catch (e, st) {
      logW(
        '⚠️ [CATALOG_BOOT] afterFirebaseMinReady falhou (type=${e.runtimeType})',
      );
      if (kDebugMode) logD('$st');
      if (mounted) {
        setState(() {
          _bootstrapErrorMessage =
              'Não foi possível carregar a loja agora. Tente novamente.';
          _bootstrapTechnicalMessage = '${e.runtimeType}: $e';
          _bootstrapStack = st.toString();
        });
      }
      if (kIsWeb) {
        final uri = Uri.base;
        final payload = <String, dynamic>{
          'buildId': kCatalogDiagBuildId,
          'timestamp': DateTime.now().toIso8601String(),
          'host': uri.host,
          'path': uri.path,
          'query': uri.query,
          'userAgent': plat.Web.userAgent(),
          'error': '$e',
          'stack': '$st',
          'fase': 'lojaLoad',
          'appVersion': 'web',
        };
        plat.Web.localStorageSet('mp_last_runtime_error', jsonEncode(payload));
      }
    } finally {
      _bootstrapRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final diag = kIsWeb && Uri.base.queryParameters['diag'] == '1';
    if (_bootstrapErrorMessage != null) {
      _scheduleHtmlLoaderHandoff('catalog_error');
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.store_mall_directory_outlined,
                      size: 60,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _bootstrapErrorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (diag && _bootstrapTechnicalMessage != null) ...[
                      const SizedBox(height: 10),
                      SelectableText(
                        'buildId=$kCatalogDiagBuildId\n'
                        'host=${Uri.base.host}\n'
                        'path=${Uri.base.path}\n'
                        'query=${Uri.base.query}\n'
                        'userAgent=${plat.Web.userAgent()}\n'
                        'error=$_bootstrapTechnicalMessage\n'
                        'stack=${_bootstrapStack ?? ''}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _startBootstrap,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return CatalogBootstrapLoadingApp(
      nomeLoja: _nomeLoja,
      logoUrl: _logoUrl,
      loadingContext: WebInitialLoadingContext.catalog,
    );
  }
}
