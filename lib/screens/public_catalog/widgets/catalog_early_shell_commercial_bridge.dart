// Bridge usado por PublicCatalogScreen enquanto o config stream está waiting.
// Propaga commercialName para CatalogEarlyShellView sem depender do HTML oculto.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../catalog/catalog_loading_store_name_sync.dart';
import '../../../core/store_display_name_resolver.dart';
import 'catalog_early_shell_view.dart';

/// Fetch injectável (testes). Produção usa [syncCatalogLoaderStoreName].
typedef CatalogCommercialNameFetcher = Future<String?> Function(String lojaId);

/// Pai real da pill LIVE durante loading: fetch → estado sticky → early shell.
///
/// Handoff HTML só após o first frame do shell **e** o fetch ter terminado
/// (sucesso ou falha), para a pill canvas já poder mostrar o nome comercial.
class CatalogEarlyShellCommercialBridge extends StatefulWidget {
  const CatalogEarlyShellCommercialBridge({
    super.key,
    required this.storeSlug,
    required this.lojaId,
    this.themeData,
    this.fetchCommercialName,
    this.onHtmlHandoffReady,
  });

  final String storeSlug;

  /// ID canónico / slug da loja — isola o estado sticky entre lojas.
  final String lojaId;
  final ThemeData? themeData;

  /// Se null, usa [syncCatalogLoaderStoreName] (1 leitura por lojaId).
  final CatalogCommercialNameFetcher? fetchCommercialName;

  /// Chamado quando a pill Flutter está pronta para substituir o HTML.
  final VoidCallback? onHtmlHandoffReady;

  @override
  State<CatalogEarlyShellCommercialBridge> createState() =>
      CatalogEarlyShellCommercialBridgeState();
}

@visibleForTesting
class CatalogEarlyShellCommercialBridgeState
    extends State<CatalogEarlyShellCommercialBridge> {
  String? _commercialName;
  String? _syncForLojaId;
  bool _syncStarted = false;
  bool _syncDone = false;
  bool _shellFirstFrameSeen = false;
  bool _handoffNotified = false;

  /// Nome sticky da loja actual (testes / inspeção).
  @visibleForTesting
  String? get commercialNameForTest => _commercialName;

  @visibleForTesting
  bool get syncDoneForTest => _syncDone;

  CatalogCommercialNameFetcher get _fetcher =>
      widget.fetchCommercialName ??
      ((id) => syncCatalogLoaderStoreName(lojaIdOrSlug: id));

  @override
  void initState() {
    super.initState();
    _ensureSync(widget.lojaId);
  }

  @override
  void didUpdateWidget(covariant CatalogEarlyShellCommercialBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.lojaId.trim();
    final prev = oldWidget.lojaId.trim();
    if (next != prev) {
      // Troca de loja: não vazar nome da loja A para B.
      _commercialName = null;
      _syncForLojaId = null;
      _syncStarted = false;
      _syncDone = false;
      _shellFirstFrameSeen = false;
      _handoffNotified = false;
      _ensureSync(next);
    }
  }

  void _ensureSync(String lojaIdOrSlug) {
    final id = lojaIdOrSlug.trim();
    if (id.isEmpty) {
      _syncDone = true;
      return;
    }
    if (_syncForLojaId == id && _syncStarted) return;
    _syncForLojaId = id;
    _syncStarted = true;
    _syncDone = false;
    unawaited(_runFetch(id));
  }

  Future<void> _runFetch(String id) async {
    String? name;
    try {
      name = await _fetcher(id);
    } catch (_) {
      name = null;
    }
    if (!mounted) return;
    if (_syncForLojaId != id) return;

    final sticky = StoreDisplayNameResolver.normalizeCandidate(name);
    setState(() {
      if (sticky != null &&
          !StoreDisplayNameResolver.isWeakPlaceholder(sticky)) {
        // Sticky: não regride a null enquanto o lojaId for o mesmo.
        _commercialName = sticky;
      }
      // Falha/vazio: mantém null → early shell usa slug fallback.
      _syncDone = true;
    });
    _maybeNotifyHandoff();
  }

  void _onShellFirstFrame() {
    if (_shellFirstFrameSeen) return;
    _shellFirstFrameSeen = true;
    _maybeNotifyHandoff();
  }

  void _maybeNotifyHandoff() {
    if (_handoffNotified) return;
    if (!_shellFirstFrameSeen || !_syncDone) return;
    _handoffNotified = true;
    widget.onHtmlHandoffReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    return CatalogEarlyShellView(
      storeSlug: widget.storeSlug,
      commercialName: _commercialName,
      themeData: widget.themeData,
      onFirstFrame: _onShellFirstFrame,
    );
  }
}
