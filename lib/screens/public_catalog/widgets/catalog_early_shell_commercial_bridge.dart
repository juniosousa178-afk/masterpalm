// Bridge: slug → lojaId → fetch nome → sticky → CatalogEarlyShellView.
// Handoff HTML só após estado TERMINAL de resolução (não só “fetch acabou”).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../catalog/catalog_loader_name_resolution.dart';
import '../../../catalog/catalog_loading_store_name_sync.dart';
import '../../../core/store_display_name_resolver.dart';
import 'catalog_early_shell_view.dart';

/// Fetch injectável (testes). Produção usa [syncCatalogLoaderStoreName].
typedef CatalogCommercialNameFetcher = Future<String?> Function(String lojaId);

/// Default: slug da URL já é o document id (padrão MasterPalm loja pública).
Future<String> defaultCatalogEarlySlugToLojaId(String slug) async {
  return slug.trim();
}

/// Pai da pill LIVE durante loading (resolve lojaId + config waiting).
///
/// Independente do config stream para o **nome** da pill: só usa [lojaId]/slug.
class CatalogEarlyShellCommercialBridge extends StatefulWidget {
  const CatalogEarlyShellCommercialBridge({
    super.key,
    required this.storeSlug,
    required this.lojaId,
    this.themeData,
    this.fetchCommercialName,
    this.resolveLojaIdFromSlug,
    this.onHtmlHandoffReady,
    this.onResolutionChanged,
  });

  final String storeSlug;

  /// ID provisório ou canónico — isola sticky entre lojas.
  final String lojaId;
  final ThemeData? themeData;

  /// Se null, usa [syncCatalogLoaderStoreName] (≤1 leitura por lojaId).
  final CatalogCommercialNameFetcher? fetchCommercialName;

  /// Se null, [defaultCatalogEarlySlugToLojaId] (slug → id).
  final CatalogEarlySlugToLojaIdResolver? resolveLojaIdFromSlug;

  /// Chamado só com first frame + resolução em estado terminal.
  final VoidCallback? onHtmlHandoffReady;

  /// Notifica o pai a cada mudança de fase (lifetime gate do early shell).
  final ValueChanged<CatalogLoaderNameResolution>? onResolutionChanged;

  @override
  State<CatalogEarlyShellCommercialBridge> createState() =>
      CatalogEarlyShellCommercialBridgeState();
}

@visibleForTesting
class CatalogEarlyShellCommercialBridgeState
    extends State<CatalogEarlyShellCommercialBridge> {
  CatalogLoaderNameResolution _resolution = const CatalogLoaderNameResolution(
    lojaId: '',
    phase: CatalogLoaderNamePhase.unresolved,
  );
  String? _pipelineForLojaId;
  int _fetchGeneration = 0;
  bool _shellFirstFrameSeen = false;
  bool _handoffNotified = false;
  int _fetchStartsForCurrentLoja = 0;

  @visibleForTesting
  CatalogLoaderNameResolution get resolutionForTest => _resolution;

  @visibleForTesting
  String? get commercialNameForTest => _resolution.commercialName;

  @visibleForTesting
  bool get syncDoneForTest => _resolution.isTerminal;

  @visibleForTesting
  int get fetchStartsForCurrentLojaForTest => _fetchStartsForCurrentLoja;

  CatalogCommercialNameFetcher get _fetcher =>
      widget.fetchCommercialName ??
      ((id) => syncCatalogLoaderStoreName(lojaIdOrSlug: id));

  CatalogEarlySlugToLojaIdResolver get _slugResolver =>
      widget.resolveLojaIdFromSlug ?? defaultCatalogEarlySlugToLojaId;

  @override
  void initState() {
    super.initState();
    _startPipeline(widget.lojaId);
  }

  @override
  void didUpdateWidget(covariant CatalogEarlyShellCommercialBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.lojaId.trim();
    final prev = oldWidget.lojaId.trim();
    if (next != prev) {
      _shellFirstFrameSeen = false;
      _handoffNotified = false;
      _fetchStartsForCurrentLoja = 0;
      _startPipeline(next);
    } else if (widget.onResolutionChanged != oldWidget.onResolutionChanged) {
      // Pai novo / callback novo (ex.: GlobalKey moveu o State): re-sincronizar.
      _notifyParentResolution();
    }
  }

  void _notifyParentResolution() {
    final snap = _resolution;
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.onResolutionChanged?.call(snap);
    });
  }

  void _publishResolution(CatalogLoaderNameResolution next, {required bool notify}) {
    _resolution = next;
    if (notify) {
      _notifyParentResolution();
    }
  }

  void _startPipeline(String lojaIdOrSlug) {
    final seed = lojaIdOrSlug.trim();
    if (seed.isEmpty) {
      setState(() {
        _publishResolution(
          const CatalogLoaderNameResolution(
            lojaId: '',
            phase: CatalogLoaderNamePhase.resolvedWithoutName,
          ),
          notify: false,
        );
        _pipelineForLojaId = '';
      });
      _notifyParentResolution();
      _maybeNotifyHandoff();
      return;
    }
    // Já sticky com nome para este id — não re-fetch.
    if (_pipelineForLojaId == seed &&
        _resolution.lojaId == seed &&
        _resolution.phase == CatalogLoaderNamePhase.resolvedWithName &&
        (_resolution.commercialName ?? '').trim().isNotEmpty) {
      _notifyParentResolution();
      return;
    }
    if (_pipelineForLojaId == seed &&
        _resolution.isTerminal &&
        _resolution.lojaId == seed) {
      // Terminal sem nome / erro: não repetir no mesmo ciclo.
      _notifyParentResolution();
      return;
    }

    _pipelineForLojaId = seed;
    final gen = ++_fetchGeneration;
    setState(() {
      _publishResolution(
        CatalogLoaderNameResolution(
          lojaId: seed,
          phase: CatalogLoaderNamePhase.loading,
        ),
        notify: false,
      );
    });
    _notifyParentResolution();
    unawaited(_runPipeline(seed, gen));
  }

  Future<void> _runPipeline(String seed, int gen) async {
    String lojaId = seed;
    try {
      final resolved = (await _slugResolver(seed)).trim();
      if (resolved.isNotEmpty) lojaId = resolved;
    } catch (_) {
      if (!mounted || gen != _fetchGeneration) return;
      setState(() {
        _publishResolution(
          CatalogLoaderNameResolution(
            lojaId: seed,
            phase: CatalogLoaderNamePhase.errorFallback,
          ),
          notify: false,
        );
      });
      _notifyParentResolution();
      _maybeNotifyHandoff();
      return;
    }

    if (!mounted || gen != _fetchGeneration) return;
    if (_pipelineForLojaId != seed) return;

    // Se já sticky com nome para o id resolvido, não ler de novo.
    if (_resolution.lojaId == lojaId &&
        _resolution.phase == CatalogLoaderNamePhase.resolvedWithName &&
        (_resolution.commercialName ?? '').isNotEmpty) {
      _notifyParentResolution();
      _maybeNotifyHandoff();
      return;
    }

    _fetchStartsForCurrentLoja++;
    String? name;
    var errored = false;
    try {
      name = await _fetcher(lojaId);
    } catch (_) {
      errored = true;
      name = null;
    }

    if (!mounted || gen != _fetchGeneration) return;
    if (_pipelineForLojaId != seed) return;

    final sticky = StoreDisplayNameResolver.normalizeCandidate(name);
    final hasName = sticky != null &&
        !StoreDisplayNameResolver.isWeakPlaceholder(sticky);

    setState(() {
      if (hasName) {
        _publishResolution(
          CatalogLoaderNameResolution(
            lojaId: lojaId,
            phase: CatalogLoaderNamePhase.resolvedWithName,
            commercialName: sticky,
          ),
          notify: false,
        );
      } else if (errored) {
        _publishResolution(
          CatalogLoaderNameResolution(
            lojaId: lojaId,
            phase: CatalogLoaderNamePhase.errorFallback,
          ),
          notify: false,
        );
      } else {
        _publishResolution(
          CatalogLoaderNameResolution(
            lojaId: lojaId,
            phase: CatalogLoaderNamePhase.resolvedWithoutName,
          ),
          notify: false,
        );
      }
    });
    _notifyParentResolution();
    _maybeNotifyHandoff();
  }

  void _onShellFirstFrame() {
    if (_shellFirstFrameSeen) return;
    _shellFirstFrameSeen = true;
    _maybeNotifyHandoff();
  }

  void _maybeNotifyHandoff() {
    if (_handoffNotified) return;
    if (!_shellFirstFrameSeen) return;
    if (!_resolution.allowsHtmlHandoff) return;
    _handoffNotified = true;
    widget.onHtmlHandoffReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    return CatalogEarlyShellView(
      storeSlug: widget.storeSlug,
      commercialName: _resolution.commercialName,
      themeData: widget.themeData,
      onFirstFrame: _onShellFirstFrame,
    );
  }
}
