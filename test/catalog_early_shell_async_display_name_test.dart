import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_loader_name_resolution.dart';
import 'package:master_palm/core/catalog_loading_store_name.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_early_shell_view.dart';
import 'package:master_palm/screens/public_catalog/widgets/catalog_unified_loading.dart';

/// Harness que simula o estado reativo de PublicCatalogScreen._loaderCommercialName.
class _AsyncPillHost extends StatefulWidget {
  const _AsyncPillHost({
    required this.slug,
    this.delayedCommercialName,
    this.delay = const Duration(milliseconds: 40),
    this.failFetch = false,
  });

  final String slug;
  final String? delayedCommercialName;
  final Duration delay;
  final bool failFetch;

  @override
  State<_AsyncPillHost> createState() => _AsyncPillHostState();
}

class _AsyncPillHostState extends State<_AsyncPillHost> {
  String? commercialName;
  CatalogLoaderNamePhase phase = CatalogLoaderNamePhase.loading;

  @override
  void initState() {
    super.initState();
    // Espelha syncCatalogLoaderStoreName: 1 fetch, depois setState (não por rebuild).
    unawaited(Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      if (widget.failFetch) {
        setState(() => phase = CatalogLoaderNamePhase.errorFallback);
        return;
      }
      final n = (widget.delayedCommercialName ?? '').trim();
      if (n.isEmpty) {
        setState(() => phase = CatalogLoaderNamePhase.resolvedWithoutName);
        return;
      }
      setState(() {
        commercialName = n;
        phase = CatalogLoaderNamePhase.resolvedWithName;
      });
    }));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CatalogEarlyShellView(
        storeSlug: widget.slug,
        commercialName: commercialName,
        namePhase: phase,
      ),
    );
  }
}

void main() {
  group('CatalogEarlyShellView async display name (LIVE /loja/{slug})', () {
    testWidgets(
      'T0 loading → no slug flash; T1 commercial arrives → pill rebuilds',
      (tester) async {
        await tester.pumpWidget(
          const _AsyncPillHost(
            slug: 'crisdealbuquerque094',
            delayedCommercialName: 'Cristal Pratas',
            delay: Duration(milliseconds: 50),
          ),
        );

        // BUILD 1 — nome ainda unavailable: pill oculta (sem slug)
        expect(find.text('Crisdealbuquerque094'), findsNothing);
        expect(find.text('Cristal Pratas'), findsNothing);
        expect(find.byKey(const Key('catalog_loading_store_pill')), findsNothing);
        expect(find.text(CatalogUnifiedLoadingCopy.title), findsOneWidget);

        // T1 — fetch conclui
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump();

        // BUILD 2
        expect(find.text('Cristal Pratas'), findsOneWidget);
        expect(find.text('Crisdealbuquerque094'), findsNothing);
      },
    );

    testWidgets('delayed store fetch keeps pill hidden until commercial',
        (tester) async {
      await tester.pumpWidget(
        const _AsyncPillHost(
          slug: 'crisdealbuquerque094',
          delayedCommercialName: 'Cristal Pratas',
          delay: Duration(milliseconds: 120),
        ),
      );

      expect(find.text('Crisdealbuquerque094'), findsNothing);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Crisdealbuquerque094'), findsNothing);
      expect(find.text('Cristal Pratas'), findsNothing);

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      expect(find.text('Cristal Pratas'), findsOneWidget);
      expect(find.text('Crisdealbuquerque094'), findsNothing);
    });

    testWidgets('Cristal Pratas async display after load', (tester) async {
      await tester.pumpWidget(
        const _AsyncPillHost(
          slug: 'crisdealbuquerque094',
          delayedCommercialName: 'Cristal Pratas',
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text('Cristal Pratas'), findsOneWidget);
    });

    testWidgets('generic async display without client hardcode', (tester) async {
      await tester.pumpWidget(
        const _AsyncPillHost(
          slug: 'maria123',
          delayedCommercialName: 'Loja da Maria',
        ),
      );
      expect(find.text('Maria123'), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text('Loja da Maria'), findsOneWidget);
      expect(find.text('Maria123'), findsNothing);
    });

    testWidgets('failed fetch releases slug fallback only after terminal',
        (tester) async {
      await tester.pumpWidget(
        const _AsyncPillHost(
          slug: 'crisdealbuquerque094',
          delayedCommercialName: 'Cristal Pratas',
          failFetch: true,
        ),
      );
      expect(find.text('Crisdealbuquerque094'), findsNothing);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      expect(find.text('Crisdealbuquerque094'), findsOneWidget);
      expect(find.text('Cristal Pratas'), findsNothing);
      expect(find.text(''), findsNothing);
    });

    testWidgets('valid name does not revert to slug fallback', (tester) async {
      await tester.pumpWidget(
        const _AsyncPillHost(
          slug: 'crisdealbuquerque094',
          delayedCommercialName: 'Cristal Pratas',
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text('Cristal Pratas'), findsOneWidget);

      // Rebuild host with same commercial name still set (simula rebuild pai).
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogEarlyShellView(
            storeSlug: 'crisdealbuquerque094',
            commercialName: 'Cristal Pratas',
            namePhase: CatalogLoaderNamePhase.resolvedWithName,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Cristal Pratas'), findsOneWidget);
      expect(find.text('Crisdealbuquerque094'), findsNothing);
    });

    test('resolveVisiblePillLabel hides slug while loading', () {
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: false,
          commercialName: null,
          slug: 'crisdealbuquerque094',
        ),
        isNull,
      );
      expect(
        CatalogLoadingStoreName.resolveVisiblePillLabel(
          allowSlugFallback: false,
          commercialName: 'Cristal Pratas',
          slug: 'crisdealbuquerque094',
        ),
        'Cristal Pratas',
      );
    });
  });
}
