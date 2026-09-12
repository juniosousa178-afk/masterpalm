import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_loader_name_resolution.dart';
import 'package:master_palm/core/catalog_loading_store_name.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_commercial_bridge.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_unified_loading.dart';

const _cristalSlug = 'crisdealbuquerque094';

String get _cristalFallback =>
    CatalogLoadingStoreName.slugToStoreNameFallback(_cristalSlug);

Finder _visiblePillText(String text) {
  return find.descendant(
    of: find.byKey(const Key('catalog_loading_store_pill')),
    matching: find.text(text),
  );
}

/// Simula PublicCatalogScreen em config waiting + lojaId ainda a resolver.
class _EarlyPipelineHost extends StatefulWidget {
  const _EarlyPipelineHost({
    required this.slug,
    required this.resolveLojaId,
    required this.fetchName,
  });

  final String slug;
  final CatalogEarlySlugToLojaIdResolver resolveLojaId;
  final CatalogCommercialNameFetcher fetchName;

  @override
  State<_EarlyPipelineHost> createState() => _EarlyPipelineHostState();
}

class _EarlyPipelineHostState extends State<_EarlyPipelineHost> {
  int handoff = 0;

  @override
  Widget build(BuildContext context) {
    // Config stream waiting: NÃO montamos catálogo final.
    return MaterialApp(
      home: CatalogEarlyShellCommercialBridge(
        storeSlug: widget.slug,
        lojaId: widget.slug, // T0: só slug; resolver antecipa lojaId
        resolveLojaIdFromSlug: widget.resolveLojaId,
        fetchCommercialName: widget.fetchName,
        onHtmlHandoffReady: () => handoff++,
      ),
    );
  }
}

void main() {
  group('early name resolution (35f0420 regression / live timing)', () {
    testWidgets(
      'FULL PIPELINE: slug→lojaId→fetch→sticky→visible pill while waiting',
      (tester) async {
        final lojaIdCompleter = Completer<String>();
        final nameCompleter = Completer<String?>();
        var fetchCount = 0;
        var resolveCount = 0;

        await tester.pumpWidget(
          _EarlyPipelineHost(
            slug: _cristalSlug,
            resolveLojaId: (slug) async {
              resolveCount++;
              expect(slug, _cristalSlug);
              return lojaIdCompleter.future;
            },
            fetchName: (id) async {
              fetchCount++;
              expect(id, _cristalSlug);
              return nameCompleter.future;
            },
          ),
        );
        await tester.pump();

        // T1 early shell montado; T2/T3 ainda sem nome — sem flash de slug.
        expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
        expect(find.text(_cristalFallback), findsNothing);
        expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);
        expect(_visiblePillText('Cristal Pratas'), findsNothing);
        expect(resolveCount, 1);
        expect(fetchCount, 0); // fetch só após lojaId

        // T4 slug resolver conclui lojaId (ainda early shell montado).
        lojaIdCompleter.complete(_cristalSlug);
        await tester.pump();
        await tester.pump();
        expect(fetchCount, 1);
        expect(find.text(_cristalFallback), findsNothing);

        // T5 nome chega com early shell montado.
        nameCompleter.complete('Cristal Pratas');
        await tester.pump();
        await tester.pump();

        // T6 pill Flutter VISÍVEL (Key scoped — não DOM/HTML oculto).
        expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
        expect(_visiblePillText(_cristalFallback), findsNothing);
        expect(fetchCount, 1);

        final state = tester.state<CatalogEarlyShellCommercialBridgeState>(
          find.byType(CatalogEarlyShellCommercialBridge),
        );
        expect(
          state.resolutionForTest.phase,
          CatalogLoaderNamePhase.resolvedWithName,
        );
        expect(state.resolutionForTest.commercialName, 'Cristal Pratas');
      },
    );

    testWidgets('handoff waits for TERMINAL resolution (not fetch-complete-null alone)',
        (tester) async {
      final nameCompleter = Completer<String?>();
      var handoff = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: _cristalSlug,
            lojaId: _cristalSlug,
            resolveLojaIdFromSlug: (s) async => s,
            fetchCommercialName: (_) => nameCompleter.future,
            onHtmlHandoffReady: () => handoff++,
          ),
        ),
      );
      await tester.pump();
      expect(handoff, 0);
      expect(find.text(_cristalFallback), findsNothing);
      expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);

      nameCompleter.complete('Cristal Pratas');
      await tester.pump();
      await tester.pump();
      expect(handoff, 1);
      expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
    });

    testWidgets('handoff does NOT fire while UNRESOLVED/LOADING', (tester) async {
      final never = Completer<String?>();
      var handoff = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: _cristalSlug,
            lojaId: _cristalSlug,
            fetchCommercialName: (_) => never.future,
            onHtmlHandoffReady: () => handoff++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(handoff, 0);
    });

    testWidgets('store without name settles to fallback (no deadlock)',
        (tester) async {
      var handoff = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: _cristalSlug,
            lojaId: _cristalSlug,
            fetchCommercialName: (_) async => null,
            onHtmlHandoffReady: () => handoff++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText(_cristalFallback), findsOneWidget);
      expect(handoff, 1);
      final state = tester.state<CatalogEarlyShellCommercialBridgeState>(
        find.byType(CatalogEarlyShellCommercialBridge),
      );
      expect(
        state.resolutionForTest.phase,
        CatalogLoaderNamePhase.resolvedWithoutName,
      );
    });

    testWidgets('fetch error settles to ERROR_FALLBACK', (tester) async {
      var handoff = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: _cristalSlug,
            lojaId: _cristalSlug,
            fetchCommercialName: (_) async => throw StateError('boom'),
            onHtmlHandoffReady: () => handoff++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText(_cristalFallback), findsOneWidget);
      expect(handoff, 1);
      final state = tester.state<CatalogEarlyShellCommercialBridgeState>(
        find.byType(CatalogEarlyShellCommercialBridge),
      );
      expect(
        state.resolutionForTest.phase,
        CatalogLoaderNamePhase.errorFallback,
      );
    });

    testWidgets('cross-store: A name does not leak to B', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: 'loja-a',
            lojaId: 'loja-a',
            fetchCommercialName: (_) async => 'Loja A Comercial',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText('Loja A Comercial'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: 'loja-b',
            lojaId: 'loja-b',
            fetchCommercialName: (_) async => 'Loja B Comercial',
          ),
        ),
      );
      await tester.pump();
      expect(_visiblePillText('Loja A Comercial'), findsNothing);
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText('Loja B Comercial'), findsOneWidget);
    });

    testWidgets('fast name resolution race-safe (before/around first frame)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: _cristalSlug,
            lojaId: _cristalSlug,
            fetchCommercialName: (_) async => 'Cristal Pratas',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
    });

    testWidgets('name near unmount: no setState after dispose', (tester) async {
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

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      nameCompleter.complete('Cristal Pratas');
      await tester.pump();
      await tester.pump();
      // Sem excepção = race safe.
      expect(find.byType(CatalogEarlyShellCommercialBridge), findsNothing);
    });

    testWidgets('repeated parent rebuilds: 0 extra fetches', (tester) async {
      var fetchCount = 0;
      late void Function() bump;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              bump = () => setState(() {});
              return CatalogEarlyShellCommercialBridge(
                storeSlug: _cristalSlug,
                lojaId: _cristalSlug,
                resolveLojaIdFromSlug: (s) async => s,
                fetchCommercialName: (_) async {
                  fetchCount++;
                  return 'Cristal Pratas';
                },
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(fetchCount, 1);
      expect(_visiblePillText('Cristal Pratas'), findsOneWidget);

      bump();
      await tester.pump();
      bump();
      await tester.pump();
      expect(fetchCount, 1);
    });

    test(
      '35f0420 conceptual fail: fetch-complete-null counted as settled',
      () {
        // Documenta o bug: em 35f0420, _syncDone=true com commercialName null
        // permitia handoff. Agora só allowsHtmlHandoff em fase terminal.
        const loading = CatalogLoaderNameResolution(
          lojaId: _cristalSlug,
          phase: CatalogLoaderNamePhase.loading,
        );
        expect(loading.allowsHtmlHandoff, isFalse);

        const withName = CatalogLoaderNameResolution(
          lojaId: _cristalSlug,
          phase: CatalogLoaderNamePhase.resolvedWithName,
          commercialName: 'Cristal Pratas',
        );
        expect(withName.allowsHtmlHandoff, isTrue);

        // “Fetch acabou com null” ≈ resolvedWithoutName (terminal) — OK fallback.
        // O que NÃO pode é tratar LOADING/UNRESOLVED como settled.
        const unresolved = CatalogLoaderNameResolution(
          lojaId: _cristalSlug,
          phase: CatalogLoaderNamePhase.unresolved,
        );
        expect(unresolved.allowsHtmlHandoff, isFalse);
      },
    );
  });
}
