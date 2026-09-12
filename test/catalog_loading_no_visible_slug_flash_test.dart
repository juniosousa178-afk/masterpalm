import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_loader_name_resolution.dart';
import 'package:master_palm/core/catalog_loading_store_name.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_commercial_bridge.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_view.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_unified_loading.dart';

const _cristalSlug = 'crisdealbuquerque094';
const _cristalName = 'Cristal Pratas';

String get _cristalSlugFallback =>
    CatalogLoadingStoreName.slugToStoreNameFallback(_cristalSlug);

Finder _visiblePillText(String text) {
  return find.descendant(
    of: find.byKey(const Key('catalog_loading_store_pill')),
    matching: find.text(text),
  );
}

/// Replica o gate de lifetime (config hasData NÃO desmonta até name terminal).
class _ReloadGateHost extends StatefulWidget {
  const _ReloadGateHost({
    required this.slug,
    required this.configHasData,
    required this.fetchName,
  });

  final String slug;
  final ValueNotifier<bool> configHasData;
  final CatalogCommercialNameFetcher fetchName;

  @override
  State<_ReloadGateHost> createState() => _ReloadGateHostState();
}

class _ReloadGateHostState extends State<_ReloadGateHost> {
  CatalogLoaderNameResolution? _nameResolution;
  bool _terminalPainted = false;
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
    return MaterialApp(
      home: Scaffold(
        body: _mayShowFinal
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
              ),
      ),
    );
  }
}

void main() {
  group('no visible slug flash (loading UX)', () {
    test('unresolved phase does not expose slug', () {
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: catalogLoaderNamePhaseAllowsSlugFallback(
            CatalogLoaderNamePhase.unresolved,
          ),
          commercialName: null,
          slug: _cristalSlug,
        ),
        isNull,
      );
      expect(
        catalogLoaderNamePhaseAllowsSlugFallback(
          CatalogLoaderNamePhase.unresolved,
        ),
        isFalse,
      );
    });

    test('loading phase does not expose slug', () {
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: catalogLoaderNamePhaseAllowsSlugFallback(
            CatalogLoaderNamePhase.loading,
          ),
          commercialName: null,
          slug: _cristalSlug,
        ),
        isNull,
      );
      expect(
        catalogLoaderNamePhaseAllowsSlugFallback(
          CatalogLoaderNamePhase.loading,
        ),
        isFalse,
      );
    });

    test('resolvedWithName shows commercialName', () {
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: catalogLoaderNamePhaseAllowsSlugFallback(
            CatalogLoaderNamePhase.resolvedWithName,
          ),
          commercialName: _cristalName,
          slug: _cristalSlug,
        ),
        _cristalName,
      );
    });

    test('resolvedWithoutName releases slug fallback', () {
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: catalogLoaderNamePhaseAllowsSlugFallback(
            CatalogLoaderNamePhase.resolvedWithoutName,
          ),
          commercialName: null,
          slug: _cristalSlug,
        ),
        _cristalSlugFallback,
      );
      expect(
        catalogLoaderNamePhaseAllowsSlugFallback(
          CatalogLoaderNamePhase.resolvedWithoutName,
        ),
        isTrue,
      );
    });

    test('errorFallback releases slug fallback', () {
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: catalogLoaderNamePhaseAllowsSlugFallback(
            CatalogLoaderNamePhase.errorFallback,
          ),
          commercialName: null,
          slug: _cristalSlug,
        ),
        _cristalSlugFallback,
      );
      expect(
        catalogLoaderNamePhaseAllowsSlugFallback(
          CatalogLoaderNamePhase.errorFallback,
        ),
        isTrue,
      );
    });

    testWidgets('unresolved/loading widgets never paint slug pill',
        (tester) async {
      for (final phase in [
        CatalogLoaderNamePhase.unresolved,
        CatalogLoaderNamePhase.loading,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: CatalogEarlyShellView(
              storeSlug: _cristalSlug,
              commercialName: null,
              namePhase: phase,
            ),
          ),
        );
        await tester.pump();
        expect(find.text(_cristalSlugFallback), findsNothing);
        expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);
        expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellView(
            storeSlug: _cristalSlug,
            commercialName: _cristalName,
            namePhase: CatalogLoaderNamePhase.resolvedWithName,
          ),
        ),
      );
      await tester.pump();
      expect(_visiblePillText(_cristalName), findsOneWidget);
      expect(find.text(_cristalSlugFallback), findsNothing);
    });

    testWidgets('COLD: no slug flash then Cristal Pratas', (tester) async {
      final nameCompleter = Completer<String?>();
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: _cristalSlug,
            lojaId: _cristalSlug,
            fetchCommercialName: (_) => nameCompleter.future,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(_cristalSlugFallback), findsNothing);
      expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);
      expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);

      nameCompleter.complete(_cristalName);
      await tester.pump();
      await tester.pump();

      expect(_visiblePillText(_cristalName), findsOneWidget);
      expect(find.text(_cristalSlugFallback), findsNothing);
    });

    testWidgets(
      'RELOAD: config fast + loading name → no slug; then Cristal',
      (tester) async {
        final nameCompleter = Completer<String?>();
        final configHasData = ValueNotifier<bool>(false);

        await tester.pumpWidget(
          _ReloadGateHost(
            slug: _cristalSlug,
            configHasData: configHasData,
            fetchName: (_) => nameCompleter.future,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text(_cristalSlugFallback), findsNothing);
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);

        configHasData.value = true;
        await tester.pump();
        await tester.pump();

        expect(find.byType(CatalogEarlyShellView), findsOneWidget);
        expect(find.byKey(const Key('final_catalog_stub')), findsNothing);
        expect(find.text(_cristalSlugFallback), findsNothing);
        expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);

        nameCompleter.complete(_cristalName);
        await tester.pump();
        await tester.pump();

        expect(_visiblePillText(_cristalName), findsOneWidget);
        expect(find.byType(CatalogEarlyShellView), findsOneWidget);
        expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
        expect(find.text(_cristalSlugFallback), findsNothing);

        await tester.pump();
        expect(find.byKey(const Key('final_catalog_stub')), findsOneWidget);
      },
    );

    testWidgets(
      'HTML→Flutter name continuity: commercial preview, never slug frame',
      (tester) async {
        // Simula bridge HTML já com commercial (preview) durante loading.
        await tester.pumpWidget(
          MaterialApp(
            home: CatalogEarlyShellView(
              storeSlug: _cristalSlug,
              commercialName: _cristalName,
              namePhase: CatalogLoaderNamePhase.loading,
            ),
          ),
        );
        await tester.pump();
        expect(_visiblePillText(_cristalName), findsOneWidget);
        expect(find.text(_cristalSlugFallback), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            home: CatalogEarlyShellView(
              storeSlug: _cristalSlug,
              commercialName: _cristalName,
              namePhase: CatalogLoaderNamePhase.resolvedWithName,
            ),
          ),
        );
        await tester.pump();
        expect(_visiblePillText(_cristalName), findsOneWidget);
        expect(find.text(_cristalSlugFallback), findsNothing);

        // Handoff para catálogo final: nenhum frame com slug.
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(child: Text('FINAL_CATALOG')),
          ),
        );
        await tester.pump();
        expect(find.text(_cristalSlugFallback), findsNothing);
        expect(find.text('FINAL_CATALOG'), findsOneWidget);
      },
    );

    test('generic loja: Joana Joias without client hardcode', () {
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: false,
          commercialName: null,
          slug: 'lojajoana123',
        ),
        isNull,
      );
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: false,
          commercialName: 'Joana Joias',
          slug: 'lojajoana123',
        ),
        'Joana Joias',
      );
    });

    test('lifetime gate still requires terminal name phase', () {
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: _cristalSlug,
            phase: CatalogLoaderNamePhase.loading,
          ),
        ),
        isFalse,
      );
      expect(
        catalogEarlyShellMayYieldToFinal(
          configHasData: true,
          nameResolution: const CatalogLoaderNameResolution(
            lojaId: _cristalSlug,
            phase: CatalogLoaderNamePhase.resolvedWithName,
            commercialName: _cristalName,
          ),
        ),
        isTrue,
      );
    });
  });
}
