import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_loader_name_resolution.dart';
import 'package:master_palm/core/catalog_loading_store_name.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_commercial_bridge.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_view.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_unified_loading.dart';

const _cristalSlug = 'crisdealbuquerque094';

Finder _visiblePillText(String text) {
  return find.descendant(
    of: find.byKey(const Key('catalog_loading_store_pill')),
    matching: find.text(text),
  );
}

/// Replica o gate de lifetime do PublicCatalogScreen (Web):
/// config hasData NÃO substitui early shell até name phase terminal.
class _LifetimeGateHost extends StatefulWidget {
  const _LifetimeGateHost({
    required this.slug,
    required this.configHasData,
    required this.fetchName,
  });

  final String slug;
  final ValueNotifier<bool> configHasData;
  final CatalogCommercialNameFetcher fetchName;

  @override
  State<_LifetimeGateHost> createState() => _LifetimeGateHostState();
}

class _LifetimeGateHostState extends State<_LifetimeGateHost> {
  CatalogLoaderNameResolution? _nameResolution;
  bool _terminalPainted = false;
  int handoff = 0;
  final GlobalKey _bridgeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.configHasData.addListener(_onConfig);
  }

  @override
  void dispose() {
    widget.configHasData.removeListener(_onConfig);
    super.dispose();
  }

  void _onConfig() => setState(() {});

  void _onResolution(CatalogLoaderNameResolution next) {
    if (!mounted) return;
    final prev = _nameResolution;
    if (prev != null &&
        prev.phase == next.phase &&
        prev.commercialName == next.commercialName &&
        prev.lojaId == next.lojaId) {
      return;
    }
    final becameTerminal = next.isTerminal && !(prev?.isTerminal ?? false);
    setState(() {
      _nameResolution = next;
      if (!next.isTerminal) _terminalPainted = false;
    });
    if (becameTerminal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_nameResolution?.isTerminal != true) return;
        setState(() => _terminalPainted = true);
      });
    }
  }

  bool get _mayShowFinal =>
      catalogEarlyShellMayYieldToFinal(
        configHasData: widget.configHasData.value,
        nameResolution: _nameResolution,
      ) &&
      _terminalPainted;

  @override
  Widget build(BuildContext context) {
    final showFinal = _mayShowFinal;
    return MaterialApp(
      home: Scaffold(
        body: showFinal
            ? const Center(
                key: Key('final_catalog_stub'),
                child: Text('FINAL_CATALOG'),
              )
            : CatalogEarlyShellCommercialBridge(
                key: _bridgeKey,
                storeSlug: widget.slug,
                lojaId: widget.slug,
                fetchCommercialName: widget.fetchName,
                onResolutionChanged: _onResolution,
                onHtmlHandoffReady: () => handoff++,
              ),
      ),
    );
  }
}

void main() {
  group('early shell name-phase lifetime gate (4fa8eb8 reload race)', () {
    test('gate helper: terminal phase required, not non-null name', () {
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: null,
        ),
        isFalse,
      );
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: 'x',
            phase: CatalogLoaderNamePhase.loading,
          ),
        ),
        isFalse,
      );
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: 'x',
            phase: CatalogLoaderNamePhase.unresolved,
          ),
        ),
        isFalse,
      );
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: 'x',
            phase: CatalogLoaderNamePhase.resolvedWithName,
            commercialName: 'Cristal Pratas',
          ),
        ),
        isTrue,
      );
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: 'x',
            phase: CatalogLoaderNamePhase.resolvedWithoutName,
          ),
        ),
        isTrue,
      );
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: 'x',
            phase: CatalogLoaderNamePhase.errorFallback,
          ),
        ),
        isTrue,
      );
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: false,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: 'x',
            phase: CatalogLoaderNamePhase.resolvedWithName,
            commercialName: 'Cristal Pratas',
          ),
        ),
        isFalse,
      );
    });

    test(
      '4fa8eb8 conceptual fail: config hasData + loading yielded final',
      () {
        // Em 4fa8eb8 o StreamBuilder ia para o catálogo final só com hasData,
        // equivalente a permitir yield com phase=loading — o gate novo impede.
        const loading = CatalogLoaderNameResolution(
          lojaId: _cristalSlug,
          phase: CatalogLoaderNamePhase.loading,
        );
        const oldBehaviorWouldShowFinal = true; // config hasData sozinho
        final newGate = catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: loading,
        );
        expect(oldBehaviorWouldShowFinal, isTrue);
        expect(newGate, isFalse);
      },
    );

    testWidgets(
      'RELOAD fast-config: keeps early shell while name loading, then pill',
      (tester) async {
        final nameCompleter = Completer<String?>();
        var fetchCount = 0;
        final configHasData = ValueNotifier<bool>(false);

        await tester.pumpWidget(
          _LifetimeGateHost(
            slug: _cristalSlug,
            configHasData: configHasData,
            fetchName: (id) async {
              fetchCount++;
              return nameCompleter.future;
            },
          ),
        );
        await tester.pump();
        await tester.pump();

        // T1 early shell + fallback slug
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);
        expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
        expect(
          _visiblePillText(
            CatalogLoadingStoreName.slugToStoreNameFallback(_cristalSlug),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('final_catalog_stub')), findsNothing);

        // T3: config hasData RAPIDAMENTE enquanto name ainda loading
        configHasData.value = true;
        await tester.pump();
        await tester.pump();

        // ASSERT CENTRAL: early shell CONTINUA
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);
        expect(find.byKey(const Key('final_catalog_stub')), findsNothing);
        expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
        expect(_visiblePillText('Cristal Pratas'), findsNothing);

        // T4–T6: fetch resolve → pill Cristal Pratas ANTES do unmount
        nameCompleter.complete('Cristal Pratas');
        await tester.pump();
        await tester.pump();

        // Frame com early shell + Cristal (antes do post-frame yield)
        expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);
        expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
        expect(find.byKey(const Key('final_catalog_stub')), findsNothing);

        // Post-frame: yield ao catálogo final
        await tester.pump();
        expect(find.byKey(const Key('final_catalog_stub')), findsOneWidget);
        expect(fetchCount, 1);
      },
    );

    testWidgets(
      'COLD timing: name terminal before config keeps pill then yields',
      (tester) async {
        final nameCompleter = Completer<String?>();
        final configHasData = ValueNotifier<bool>(false);

        await tester.pumpWidget(
          _LifetimeGateHost(
            slug: _cristalSlug,
            configHasData: configHasData,
            fetchName: (_) => nameCompleter.future,
          ),
        );
        await tester.pump();

        nameCompleter.complete('Cristal Pratas');
        await tester.pump();
        await tester.pump();

        expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
        expect(find.byKey(const Key('final_catalog_stub')), findsNothing);

        configHasData.value = true;
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('final_catalog_stub')), findsOneWidget);
      },
    );

    testWidgets(
      'resolvedWithoutName releases early shell with fallback',
      (tester) async {
        final nameCompleter = Completer<String?>();
        final configHasData = ValueNotifier<bool>(true);

        await tester.pumpWidget(
          _LifetimeGateHost(
            slug: _cristalSlug,
            configHasData: configHasData,
            fetchName: (_) => nameCompleter.future,
          ),
        );
        await tester.pump();
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);

        nameCompleter.complete(null);
        await tester.pump();
        await tester.pump();

        expect(
          _visiblePillText(
            CatalogLoadingStoreName.slugToStoreNameFallback(_cristalSlug),
          ),
          findsOneWidget,
        );
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);
        expect(find.byKey(const Key('final_catalog_stub')), findsNothing);

        await tester.pump(); // post-frame yield
        expect(find.byKey(const Key('final_catalog_stub')), findsOneWidget);
      },
    );

    testWidgets(
      'errorFallback releases early shell without deadlock',
      (tester) async {
        final nameCompleter = Completer<String?>();
        final configHasData = ValueNotifier<bool>(true);

        await tester.pumpWidget(
          _LifetimeGateHost(
            slug: _cristalSlug,
            configHasData: configHasData,
            fetchName: (_) => nameCompleter.future,
          ),
        );
        await tester.pump();
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);

        nameCompleter.completeError(Exception('firestore'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);
        expect(find.byKey(const Key('final_catalog_stub')), findsNothing);

        await tester.pump(); // post-frame yield
        expect(find.byKey(const Key('final_catalog_stub')), findsOneWidget);
      },
    );

    testWidgets(
      'fetch completion near yield: no setState after dispose',
      (tester) async {
        final nameCompleter = Completer<String?>();
        final configHasData = ValueNotifier<bool>(true);

        await tester.pumpWidget(
          _LifetimeGateHost(
            slug: _cristalSlug,
            configHasData: configHasData,
            fetchName: (_) => nameCompleter.future,
          ),
        );
        await tester.pump();

        nameCompleter.complete('Cristal Pratas');
        await tester.pump();
        await tester.pump();
        expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
        await tester.pump(); // yield
        expect(find.byKey(const Key('final_catalog_stub')), findsOneWidget);

        // Extra pumps — sem exception
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      },
    );

    testWidgets(
      'GlobalKey keeps single fetch across config-ready while loading',
      (tester) async {
        final nameCompleter = Completer<String?>();
        var fetchCount = 0;
        final configHasData = ValueNotifier<bool>(false);

        await tester.pumpWidget(
          _LifetimeGateHost(
            slug: _cristalSlug,
            configHasData: configHasData,
            fetchName: (_) async {
              fetchCount++;
              return nameCompleter.future;
            },
          ),
        );
        await tester.pump();
        expect(fetchCount, 1);

        configHasData.value = true;
        await tester.pump();
        await tester.pump();
        // Shell retained; same GlobalKey → no second fetch
        expect(fetchCount, 1);
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);

        nameCompleter.complete('Cristal Pratas');
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(fetchCount, 1);
      },
    );
  });
}
