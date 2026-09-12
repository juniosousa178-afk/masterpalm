import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_loader_name_resolution.dart';
import 'package:master_palm/core/catalog_loading_store_name.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_commercial_bridge.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_view.dart';
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

/// Host estável: setState do pai sem descartar o State do bridge.
class _BridgeHarness extends StatefulWidget {
  const _BridgeHarness({
    required this.lojaId,
    required this.storeSlug,
    required this.fetcher,
  });

  final String lojaId;
  final String storeSlug;
  final CatalogCommercialNameFetcher fetcher;

  @override
  State<_BridgeHarness> createState() => _BridgeHarnessState();
}

class _BridgeHarnessState extends State<_BridgeHarness> {
  late String lojaId = widget.lojaId;
  late String storeSlug = widget.storeSlug;
  late CatalogCommercialNameFetcher fetcher = widget.fetcher;
  int handoffCount = 0;

  void bump() => setState(() {});

  void switchStore({
    required String nextLojaId,
    required String nextSlug,
    required CatalogCommercialNameFetcher nextFetcher,
  }) {
    setState(() {
      lojaId = nextLojaId;
      storeSlug = nextSlug;
      fetcher = nextFetcher;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CatalogEarlyShellCommercialBridge(
        storeSlug: storeSlug,
        lojaId: lojaId,
        fetchCommercialName: fetcher,
        onHtmlHandoffReady: () => handoffCount++,
      ),
    );
  }
}

void main() {
  group('CatalogEarlyShellCommercialBridge state propagation', () {
    testWidgets(
      'fetch → setState → child rebuilds pill (not seed with name)',
      (tester) async {
        final completer = Completer<String?>();
        var fetchCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: CatalogEarlyShellCommercialBridge(
              storeSlug: _cristalSlug,
              lojaId: _cristalSlug,
              fetchCommercialName: (id) {
                fetchCalls++;
                expect(id, _cristalSlug);
                return completer.future;
              },
            ),
          ),
        );
        await tester.pump();

        expect(find.text(_cristalFallback), findsNothing);
        expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);
        expect(_visiblePillText('Cristal Pratas'), findsNothing);
        expect(fetchCalls, 1);

        completer.complete('Cristal Pratas');
        await tester.pump();
        await tester.pump();

        expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
        expect(_visiblePillText(_cristalFallback), findsNothing);
        expect(fetchCalls, 1);
      },
    );

    testWidgets('parent rebuild while waiting does not re-fetch', (tester) async {
      var fetchCalls = 0;
      final completer = Completer<String?>();

      await tester.pumpWidget(
        _BridgeHarness(
          lojaId: _cristalSlug,
          storeSlug: _cristalSlug,
          fetcher: (_) {
            fetchCalls++;
            return completer.future;
          },
        ),
      );
      await tester.pump();
      expect(fetchCalls, 1);

      final state = tester.state<_BridgeHarnessState>(find.byType(_BridgeHarness));
      state.bump();
      await tester.pump();
      expect(fetchCalls, 1);

      completer.complete('Cristal Pratas');
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
      expect(fetchCalls, 1);
    });

    testWidgets('sticky name survives parent rebuild after resolve',
        (tester) async {
      var fetchCalls = 0;
      await tester.pumpWidget(
        _BridgeHarness(
          lojaId: _cristalSlug,
          storeSlug: _cristalSlug,
          fetcher: (_) async {
            fetchCalls++;
            return 'Cristal Pratas';
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
      expect(fetchCalls, 1);

      final state = tester.state<_BridgeHarnessState>(find.byType(_BridgeHarness));
      state.bump();
      await tester.pump();
      expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
      expect(_visiblePillText(_cristalFallback), findsNothing);
      expect(fetchCalls, 1);
    });

    testWidgets('cross-store: loja A name does not leak to loja B',
        (tester) async {
      await tester.pumpWidget(
        _BridgeHarness(
          lojaId: 'loja-a',
          storeSlug: 'loja-a',
          fetcher: (_) async => 'Loja A Comercial',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText('Loja A Comercial'), findsOneWidget);

      final state = tester.state<_BridgeHarnessState>(find.byType(_BridgeHarness));
      state.switchStore(
        nextLojaId: 'loja-b',
        nextSlug: 'loja-b',
        nextFetcher: (_) async => 'Loja B Comercial',
      );
      await tester.pump();
      expect(_visiblePillText('Loja A Comercial'), findsNothing);

      // Em loading sem comercial: pill oculta (sem flash de slug de loja-b).
      expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);
      expect(
        find.text(CatalogLoadingStoreName.slugToStoreNameFallback('loja-b')),
        findsNothing,
      );

      await tester.pump();
      await tester.pump();
      expect(_visiblePillText('Loja B Comercial'), findsOneWidget);
      expect(_visiblePillText('Loja A Comercial'), findsNothing);
    });

    testWidgets('empty/fail fetch keeps slug fallback on Flutter pill',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellCommercialBridge(
            storeSlug: _cristalSlug,
            lojaId: _cristalSlug,
            fetchCommercialName: (_) async => null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_visiblePillText(_cristalFallback), findsOneWidget);
      expect(_visiblePillText('Cristal Pratas'), findsNothing);
      expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);
    });

    testWidgets('handoff waits until fetch settled (no premature notify)',
        (tester) async {
      final completer = Completer<String?>();

      await tester.pumpWidget(
        _BridgeHarness(
          lojaId: _cristalSlug,
          storeSlug: _cristalSlug,
          fetcher: (_) => completer.future,
        ),
      );
      await tester.pump();
      final state = tester.state<_BridgeHarnessState>(find.byType(_BridgeHarness));
      expect(state.handoffCount, 0);
      expect(find.text(_cristalFallback), findsNothing);
      expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);

      completer.complete('Cristal Pratas');
      await tester.pump();
      await tester.pump();
      expect(state.handoffCount, 1);
      expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
    });
  });

  group('HIDDEN_HTML_FALSE_POSITIVE_REGRESSION', () {
    testWidgets(
      'global find.text(Cristal) is polluted by Offstage; pill stays hidden while loading',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                const Offstage(child: Text('Cristal Pratas')),
                CatalogEarlyShellView(
                  storeSlug: _cristalSlug,
                  commercialName: null,
                  namePhase: CatalogLoaderNamePhase.loading,
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        // Armadilha: skipOffstage:false vê o badge oculto (HTML falso positivo).
        expect(
          find.text('Cristal Pratas', skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text(_cristalFallback), findsNothing);
        expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);
        expect(_visiblePillText('Cristal Pratas'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                const Offstage(child: Text('Cristal Pratas')),
                CatalogEarlyShellView(
                  storeSlug: _cristalSlug,
                  commercialName: 'Cristal Pratas',
                  namePhase: CatalogLoaderNamePhase.resolvedWithName,
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(_visiblePillText('Cristal Pratas'), findsOneWidget);
        expect(_visiblePillText(_cristalFallback), findsNothing);
      },
    );
  });
}
