// Diagnóstico e layout seguro para Instagram in-app browser no Android (WebView).
// Não altera checkout PIX/frete — apenas viewport, overflow e menu lateral.

import 'dart:async' show StreamSubscription, unawaited;
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../web/platform_stub.dart'
    if (dart.library.html) '../../../web/platform_web.dart' as plat;

/// Instagram Android WebView (link da bio). iPhone e Chrome Android ficam de fora.
class CatalogIgAndroidWebview {
  CatalogIgAndroidWebview._();

  static bool? _cachedActive;

  static bool get isActive {
    if (!kIsWeb) return false;
    return _cachedActive ??= plat.Web.isInstagramAndroidWebView();
  }

  /// Largura efetiva: menor entre MediaQuery, innerWidth, clientWidth e visualViewport.
  static double effectiveLayoutWidth(BuildContext context) {
    final mqW = MediaQuery.sizeOf(context).width;
    if (!isActive) return mqW;
    final metrics = plat.Web.catalogViewportMetrics();
    final candidates = <double>[
      mqW,
      _metricDouble(metrics['innerWidth']),
      _metricDouble(metrics['clientWidth']),
      _metricDouble(metrics['visualViewportWidth']),
    ].where((w) => w > 0 && w.isFinite);
    if (candidates.isEmpty) return mqW;
    return candidates.reduce(math.min);
  }

  static double _metricDouble(Object? v) {
    if (v is num) return v.toDouble();
    return 0;
  }

  static void ensureDomGuards() {
    if (!isActive) return;
    plat.Web.applyCatalogIgAndroidDomGuards();
  }

  /// Log seguro no console (sem PII). Repete só se métricas mudarem materialmente.
  static void logLayoutDiagnostics({
    required String route,
    String? lojaId,
    String? slug,
    double? layoutWidth,
    bool? drawerOpen,
    bool? cartOpen,
    bool? searchHasText,
  }) {
    if (!isActive) return;
    final metrics = plat.Web.catalogViewportMetrics();
    final payload = <String, dynamic>{
      'tag': 'IG-ANDROID-CATALOG',
      'route': route,
      'lojaId': lojaId ?? '',
      'slug': slug ?? '',
      'layoutWidth': layoutWidth,
      'userAgent': plat.Web.userAgent(),
      'innerWidth': metrics['innerWidth'],
      'innerHeight': metrics['innerHeight'],
      'clientWidth': metrics['clientWidth'],
      'clientHeight': metrics['clientHeight'],
      'devicePixelRatio': metrics['devicePixelRatio'],
      'visualViewportWidth': metrics['visualViewportWidth'],
      'visualViewportHeight': metrics['visualViewportHeight'],
      'drawerOpen': drawerOpen,
      'cartOpen': cartOpen,
      'searchHasText': searchHasText,
    };
    final line = jsonEncode(payload);
    if (kDebugMode) {
      debugPrint(line);
    }
    plat.Web.consoleLog(line);
    try {
      plat.Web.localStorageSet('mp_ig_android_catalog_diag', line);
    } catch (_) {}
  }

  static Future<void> openInExternalBrowser() async {
    if (!kIsWeb) return;
    final href = plat.Web.locationHref();
    if (href.isEmpty) return;
    final uri = Uri.parse(href);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Widget layoutHost({
    required Widget child,
    required String routeLabel,
    String? lojaId,
    String? slug,
    bool drawerOpen = false,
    bool cartOpen = false,
    bool searchHasText = false,
  }) {
    if (!isActive) return child;
    return _CatalogIgAndroidLayoutHost(
      routeLabel: routeLabel,
      lojaId: lojaId,
      slug: slug,
      drawerOpen: drawerOpen,
      cartOpen: cartOpen,
      searchHasText: searchHasText,
      child: child,
    );
  }

  static Widget wrapWidth({
    required BuildContext context,
    required Widget child,
  }) {
    if (!isActive) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = effectiveLayoutWidth(context);
        final maxParent = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : w;
        final capped = math.min(w, maxParent);
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: capped,
            child: ClipRect(
              clipBehavior: Clip.hardEdge,
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// Banner discreto para abrir no navegador externo (mesma URL canônica).
  static Widget openInBrowserBanner({required Color accent}) {
    return Material(
      color: const Color(0xFF1E293B),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.open_in_browser, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Visualização limitada no Instagram. Abra no navegador para ver o catálogo completo.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(openInExternalBrowser()),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Abrir',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogIgAndroidLayoutHost extends StatefulWidget {
  const _CatalogIgAndroidLayoutHost({
    required this.child,
    required this.routeLabel,
    this.lojaId,
    this.slug,
    this.drawerOpen = false,
    this.cartOpen = false,
    this.searchHasText = false,
  });

  final Widget child;
  final String routeLabel;
  final String? lojaId;
  final String? slug;
  final bool drawerOpen;
  final bool cartOpen;
  final bool searchHasText;

  @override
  State<_CatalogIgAndroidLayoutHost> createState() =>
      _CatalogIgAndroidLayoutHostState();
}

class _CatalogIgAndroidLayoutHostState extends State<_CatalogIgAndroidLayoutHost> {
  StreamSubscription<void>? _viewportSub;
  double _lastLoggedWidth = -1;

  @override
  void initState() {
    super.initState();
    CatalogIgAndroidWebview.ensureDomGuards();
    _viewportSub = plat.Web.listenVisualViewportResize(_onViewportChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _logOnce());
  }

  @override
  void didUpdateWidget(covariant _CatalogIgAndroidLayoutHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drawerOpen != widget.drawerOpen ||
        oldWidget.cartOpen != widget.cartOpen ||
        oldWidget.searchHasText != widget.searchHasText) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _logOnce());
    }
  }

  void _onViewportChange() {
    if (!mounted) return;
    setState(() {});
    _logOnce();
  }

  void _logOnce() {
    if (!mounted) return;
    final w = CatalogIgAndroidWebview.effectiveLayoutWidth(context);
    if ((w - _lastLoggedWidth).abs() < 2 && _lastLoggedWidth > 0) return;
    _lastLoggedWidth = w;
    CatalogIgAndroidWebview.logLayoutDiagnostics(
      route: widget.routeLabel,
      lojaId: widget.lojaId,
      slug: widget.slug,
      layoutWidth: w,
      drawerOpen: widget.drawerOpen,
      cartOpen: widget.cartOpen,
      searchHasText: widget.searchHasText,
    );
  }

  @override
  void dispose() {
    _viewportSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = CatalogIgAndroidWebview.effectiveLayoutWidth(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: Size(w, MediaQuery.sizeOf(context).height),
      ),
      child: CatalogIgAndroidWebview.wrapWidth(
        context: context,
        child: widget.child,
      ),
    );
  }
}
