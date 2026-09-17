// Suite focada: hidratação determinística do seletor de grade/variação (PDV).
// Widget tests com hydrateOnOpen evitados: CircularProgressIndicator + Hive watch
// causam hang em pump; cobertura de UI live via unidade + sheet sem hydrate async.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_grade_pdv_hydration.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_grade_pdv_hydration_service.dart';

Produto _baseProduto({
  required String lojaId,
  required String productId,
  String nome = 'Produto Teste',
  Map<String, dynamic>? variacoes,
  Map<String, int> estoquePorTamanho = const {},
  List<String> tamanhos = const [],
  double preco = 50,
}) {
  return Produto(
    nome: nome,
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: preco,
    quantidade: 1,
    precoUnitario: preco,
    categoria: 'Teste',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: lojaId,
    idFirebase: productId,
    slug: productId,
    variacoes: variacoes,
    estoquePorTamanho: estoquePorTamanho,
    tamanhos: tamanhos,
    custoEditadoNoCadastro: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late Box<Produto> box;

  setUp(() async {
    ProdutoGradePdvHydrationService.debugReset();
    hiveDir = Directory.systemTemp.createTempSync('grade_pdv_hydration_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
    box = await Hive.openBox<Produto>(
      'produtos_grade_pdv_${hiveDir.path.hashCode}',
    );
  });

  tearDown(() async {
    ProdutoGradePdvHydrationService.debugReset();
    if (box.isOpen) await box.close();
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('readiness / policy', () {
    test('PARTIAL_OBJECT: usaVariacoes=false + estoque vazio ≠ NO_VARIATION', () {
      final partial = _baseProduto(
        lojaId: 'loja-a',
        productId: 'p-partial',
        variacoes: null,
        estoquePorTamanho: const {},
      );
      expect(partial.usaVariacoes, isFalse);
      expect(partial.estoquePorTamanho, isEmpty);
      expect(
        isGradeProductHydrationComplete(
          partial,
          sessionHydratedAuthoritative: false,
        ),
        isFalse,
      );
      expect(
        evaluateGradePdvReadiness(
          produto: partial,
          sessionHydratedAuthoritative: false,
          hydrating: false,
          hydrationFailedOrOfflinePartial: false,
        ),
        GradePdvReadiness.unknown,
      );
      expect(
        evaluateGradePdvReadiness(
          produto: partial,
          sessionHydratedAuthoritative: false,
          hydrating: true,
          hydrationFailedOrOfflinePartial: false,
        ),
        GradePdvReadiness.hydrating,
      );
    });

    test('SIMPLE autoritativo só após sessionHydrated', () {
      final simple = _baseProduto(lojaId: 'loja-a', productId: 'p-simple');
      expect(
        evaluateGradePdvReadiness(
          produto: simple,
          sessionHydratedAuthoritative: true,
          hydrating: false,
          hydrationFailedOrOfflinePartial: false,
        ),
        GradePdvReadiness.readyWithoutVariation,
      );
    });

    test('sinal positivo local → READY_WITH_VARIATION', () {
      final grade = _baseProduto(
        lojaId: 'loja-a',
        productId: 'p-grade',
        estoquePorTamanho: const {'M': 2},
        tamanhos: const ['M'],
      );
      expect(
        evaluateGradePdvReadiness(
          produto: grade,
          sessionHydratedAuthoritative: false,
          hydrating: false,
          hydrationFailedOrOfflinePartial: false,
        ),
        GradePdvReadiness.readyWithVariation,
      );
    });
  });

  group('targeted hydration service', () {
    test('PARTIAL + remote variation → READY_WITH_VARIATION (STALE usaVariacoes)',
        () async {
      final partial = _baseProduto(lojaId: 'loja-a', productId: 'p-var');
      await box.add(partial);

      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => true;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {
        final p = ProdutoGradePdvHydrationService.findProdutoInBox(
          produtosBox: produtosBox,
          lojaId: lojaId,
          productId: productId,
        )!;
        p.variacoes = {
          'P': {'Preto': 2},
          'M': {'Preto': 1},
        };
        p.estoquePorTamanho = const {'P': 2, 'M': 1};
        p.tamanhos = ['P', 'M'];
        await p.save();
      };

      // OPEN_BEFORE_SYNC: partial ainda unknown/hydrating semanticamente
      expect(
        evaluateGradePdvReadiness(
          produto: partial,
          sessionHydratedAuthoritative: false,
          hydrating: true,
          hydrationFailedOrOfflinePartial: false,
        ),
        GradePdvReadiness.hydrating,
      );

      final result = await ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-var',
        produtosBox: box,
        seed: partial,
      );

      expect(result.readiness, GradePdvReadiness.readyWithVariation);
      expect(result.produto!.usaVariacoes, isTrue);
      expect(
        ProdutoGradePdvHydrationService.isSessionAuthoritative(
          lojaId: 'loja-a',
          productId: 'p-var',
        ),
        isTrue,
      );

      // LIVE_REHYDRATION: mesmo productId, após hydrate, seletor disponível
      // sem close/reopen (reopen seria idêntico).
      final reopen = await ProdutoGradePdvHydrationService.resolveForPdvSelection(
        lojaId: 'loja-a',
        seed: result.produto!,
        produtosBox: box,
      );
      expect(reopen.readiness, GradePdvReadiness.readyWithVariation);
    });

    test('STALE estoquePorTamanho {} + remote grade → READY_WITH_VARIATION',
        () async {
      final partial = _baseProduto(lojaId: 'loja-a', productId: 'p-grade');
      await box.add(partial);

      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => true;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {
        final p = ProdutoGradePdvHydrationService.findProdutoInBox(
          produtosBox: produtosBox,
          lojaId: lojaId,
          productId: productId,
        )!;
        p.estoquePorTamanho = const {'36': 1, '37': 2};
        p.tamanhos = ['36', '37'];
        await p.save();
      };

      final result = await ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-grade',
        produtosBox: box,
        seed: partial,
      );
      expect(result.readiness, GradePdvReadiness.readyWithVariation);
      expect(result.produto!.estoquePorTamanho.isNotEmpty, isTrue);
    });

    test('VARIATION product path', () async {
      final variation = _baseProduto(
        lojaId: 'loja-a',
        productId: 'p-cores',
        variacoes: {
          'M': {'Azul': 2},
        },
      );
      final r = await ProdutoGradePdvHydrationService.resolveForPdvSelection(
        lojaId: 'loja-a',
        seed: variation,
        produtosBox: box,
      );
      expect(r.readiness, GradePdvReadiness.readyWithVariation);
    });

    test('GRADE product path', () async {
      final grade = _baseProduto(
        lojaId: 'loja-a',
        productId: 'p-size',
        estoquePorTamanho: const {'38': 2},
      );
      final r = await ProdutoGradePdvHydrationService.resolveForPdvSelection(
        lojaId: 'loja-a',
        seed: grade,
        produtosBox: box,
      );
      expect(r.readiness, GradePdvReadiness.readyWithVariation);
    });

    test('SIMPLE remoto → READY_WITHOUT_VARIATION', () async {
      final partial = _baseProduto(lojaId: 'loja-a', productId: 'p-simple');
      await box.add(partial);
      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => true;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {};

      final result = await ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-simple',
        produtosBox: box,
        seed: partial,
      );
      expect(result.readiness, GradePdvReadiness.readyWithoutVariation);
    });

    test('OFFLINE complete cache → READY_WITH_VARIATION', () async {
      final complete = _baseProduto(
        lojaId: 'loja-a',
        productId: 'p-off-ok',
        estoquePorTamanho: const {'M': 3},
        tamanhos: const ['M'],
      );
      await box.add(complete);
      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => false;

      final result = await ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-off-ok',
        produtosBox: box,
        seed: complete,
      );
      expect(result.readiness, GradePdvReadiness.readyWithVariation);
    });

    test('OFFLINE partial → offlinePartial (não SIMPLE)', () async {
      final partial = _baseProduto(lojaId: 'loja-a', productId: 'p-off-bad');
      await box.add(partial);
      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => false;

      final result = await ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-off-bad',
        produtosBox: box,
        seed: partial,
      );
      expect(result.readiness, GradePdvReadiness.offlinePartial);
      expect(
        ProdutoGradePdvHydrationService.isSessionAuthoritative(
          lojaId: 'loja-a',
          productId: 'p-off-bad',
        ),
        isFalse,
      );
    });

    test('CONCURRENT dedupe: uma única remote hydrate', () async {
      final partial = _baseProduto(lojaId: 'loja-a', productId: 'p-dedupe');
      await box.add(partial);
      var calls = 0;
      final gate = Completer<void>();
      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => true;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {
        calls++;
        await gate.future;
        final p = ProdutoGradePdvHydrationService.findProdutoInBox(
          produtosBox: produtosBox,
          lojaId: lojaId,
          productId: productId,
        )!;
        p.variacoes = {
          'U': {'sem-cor': 1},
        };
        await p.save();
      };

      final f1 = ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-dedupe',
        produtosBox: box,
        seed: partial,
      );
      final f2 = ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-dedupe',
        produtosBox: box,
        seed: partial,
      );
      gate.complete();
      final r1 = await f1;
      final r2 = await f2;
      expect(calls, 1);
      expect(r1.readiness, GradePdvReadiness.readyWithVariation);
      expect(r2.readiness, GradePdvReadiness.readyWithVariation);
    });

    test('STALE async A não sobrescreve B (chave por productId)', () async {
      final a = _baseProduto(lojaId: 'loja-a', productId: 'prod-a', nome: 'A');
      final b = _baseProduto(lojaId: 'loja-a', productId: 'prod-b', nome: 'B');
      await box.add(a);
      await box.add(b);

      final gateA = Completer<void>();
      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => true;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {
        if (productId == 'prod-a') {
          await gateA.future;
          final p = ProdutoGradePdvHydrationService.findProdutoInBox(
            produtosBox: produtosBox,
            lojaId: lojaId,
            productId: productId,
          )!;
          p.variacoes = {
            'A': {'x': 1},
          };
          await p.save();
        } else {
          final p = ProdutoGradePdvHydrationService.findProdutoInBox(
            produtosBox: produtosBox,
            lojaId: lojaId,
            productId: productId,
          )!;
          p.variacoes = {
            'B': {'y': 2},
          };
          await p.save();
        }
      };

      final futA = ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'prod-a',
        produtosBox: box,
        seed: a,
      );
      final futB = ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'prod-b',
        produtosBox: box,
        seed: b,
      );
      final rB = await futB;
      expect(rB.productId, 'prod-b');
      expect(rB.produto!.variacoes!.containsKey('B'), isTrue);

      gateA.complete();
      final rA = await futA;
      expect(rA.productId, 'prod-a');

      final liveB = ProdutoGradePdvHydrationService.findProdutoInBox(
        produtosBox: box,
        lojaId: 'loja-a',
        productId: 'prod-b',
      )!;
      expect(liveB.variacoes!.containsKey('B'), isTrue);
      expect(liveB.variacoes!.containsKey('A'), isFalse);
    });

    test('CROSS_STORE isolation by lojaId|productId', () async {
      final s1 = _baseProduto(lojaId: 'loja-1', productId: 'same-id');
      final s2 = _baseProduto(lojaId: 'loja-2', productId: 'same-id');
      await box.add(s1);
      await box.add(s2);

      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => true;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {
        final p = ProdutoGradePdvHydrationService.findProdutoInBox(
          produtosBox: produtosBox,
          lojaId: lojaId,
          productId: productId,
        )!;
        if (lojaId == 'loja-1') {
          p.variacoes = {
            'L1': {'sem-cor': 1},
          };
        }
        await p.save();
      };

      final r1 = await ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-1',
        productId: 'same-id',
        produtosBox: box,
        seed: s1,
      );
      final r2 = await ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-2',
        productId: 'same-id',
        produtosBox: box,
        seed: s2,
      );
      expect(r1.readiness, GradePdvReadiness.readyWithVariation);
      expect(r2.readiness, GradePdvReadiness.readyWithoutVariation);
    });

    test('resolveForPdvSelection: local grade abre sem remote', () async {
      final grade = _baseProduto(
        lojaId: 'loja-a',
        productId: 'p-local',
        estoquePorTamanho: const {'38': 1},
      );
      var remoteCalls = 0;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {
        remoteCalls++;
      };
      final r = await ProdutoGradePdvHydrationService.resolveForPdvSelection(
        lojaId: 'loja-a',
        seed: grade,
        produtosBox: box,
      );
      expect(r.readiness, GradePdvReadiness.readyWithVariation);
      expect(remoteCalls, 0);
    });

    test('DISPOSE_DURING_HYDRATION: resultado tardio isolado por generation/id',
        () async {
      final partial = _baseProduto(lojaId: 'loja-a', productId: 'p-dispose');
      await box.add(partial);
      final gate = Completer<void>();
      ProdutoGradePdvHydrationService.debugOnlineCheckOverride = () async => true;
      ProdutoGradePdvHydrationService.debugRemoteHydrateOverride =
          ({required lojaId, required produtosBox, required productId}) async {
        await gate.future;
        final p = ProdutoGradePdvHydrationService.findProdutoInBox(
          produtosBox: produtosBox,
          lojaId: lojaId,
          productId: productId,
        )!;
        p.estoquePorTamanho = const {'40': 1};
        await p.save();
      };

      final fut = ProdutoGradePdvHydrationService.hydrateByProductId(
        lojaId: 'loja-a',
        productId: 'p-dispose',
        produtosBox: box,
        seed: partial,
      );
      // Simula dispose: não aguardamos na UI; late result ainda correlaciona id.
      gate.complete();
      final r = await fut;
      expect(r.productId, 'p-dispose');
      expect(r.readiness, GradePdvReadiness.readyWithVariation);
    });
  });
}

