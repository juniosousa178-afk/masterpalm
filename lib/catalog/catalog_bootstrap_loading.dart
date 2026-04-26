// Catálogo público Web: primeira pintura com loader (evita tela branca).
//
// Catálogo público não deve passar pelo bootstrap pesado do app (Hive, sessão, RemoteConfig)
// antes do primeiro frame. Isso causa tela branca e atraso.
//
// Não depende de lojaId, config nem produtos — só tema + texto.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../debug/bootstrap_diagnostics.dart';
import '../debug/catalog_startup_trace.dart';
import '../themes/app_colors.dart';
import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as plat;

/// Tela leve exibida antes de resolver domínio / Firebase mínimo.
class CatalogBootstrapLoadingScreen extends StatelessWidget {
  const CatalogBootstrapLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'MasterPalm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'Carregando catálogo...',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Estamos preparando a loja para você ✨',
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
  const CatalogBootstrapLoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      ),
      home: const CatalogBootstrapLoadingScreen(),
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
  });

  final Future<bool> Function() initFirebase;
  final Future<void> Function() afterFirebaseMinReady;

  /// Ex.: `CAT_START.fast_path.firebase_min_init` ou `CAT_START.custom_domain.fast_path.firebase`
  final String firebaseSpanName;

  @override
  State<PublicCatalogBootstrapApp> createState() =>
      _PublicCatalogBootstrapAppState();
}

class _PublicCatalogBootstrapAppState extends State<PublicCatalogBootstrapApp> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('[CATALOG_BOOT] first_frame_loader');
    }
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        plat.Web.hideInitialCatalogLoader();
      });
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    CatalogStartupTrace.spanStart(widget.firebaseSpanName);
    var firebaseOk = false;
    try {
      if (kDebugMode) debugPrint('[CATALOG_BOOT] firebase.min.begin');
      firebaseOk = await widget.initFirebase();
      if (kDebugMode) {
        debugPrint(
          '[CATALOG_BOOT] firebase.min.${firebaseOk ? 'ok' : 'fail'}',
        );
      }
      if (firebaseOk) {
        FirebaseGuard.markReady();
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
      await widget.afterFirebaseMinReady();
    } catch (e, st) {
      logW(
        '⚠️ [CATALOG_BOOT] afterFirebaseMinReady falhou (type=${e.runtimeType})',
      );
      if (kDebugMode) logD('$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const CatalogBootstrapLoadingApp();
  }
}
