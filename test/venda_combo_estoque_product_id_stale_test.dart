// Simula o bug Lavile (Relógio stale + Anel na tela) sem loja real.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/strict_product_resolution.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';

void main() {
  const lojaId = 'loja-teste-preview';
  const nomeRelogio = 'Relógio Cássio Oval';
  const nomeAnel = 'Anel Shine Regulável';
  const idRelogio = 'produto-relogio';
  const idAnel = 'produto-anel';
  const slugRelogio = 'lavile-joias-rel-gio-cassio-oval';
  const slugAnel = 'anel-shine-regulavel';

  late String hivePath;
  late Box<Produto> box;

  Produto criar({
    required String nome,
    required String idFirebase,
    required String slug,
    int quantidade = 5,
  }) {
    final p = Produto.vazio();
    p.nome = nome;
    p.idFirebase = idFirebase;
    p.slug = slug;
    p.lojaId = lojaId;
    p.quantidade = quantidade;
    return p;
  }

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_venda_stale_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    setStrictResolutionTestOverride(false);
    final boxName = 'produtos_${DateTime.now().microsecondsSinceEpoch}';
    box = await Hive.openBox<Produto>(boxName);
    await box.addAll([
      criar(nome: nomeRelogio, idFirebase: idRelogio, slug: slugRelogio),
      criar(nome: nomeAnel, idFirebase: idAnel, slug: slugAnel),
    ]);
  });

  tearDown(() async {
    setStrictResolutionTestOverride(null);
    await box.close();
  });

  group('bug Lavile — linha com nome Anel e productId stale do Relógio', () {
    test('helper detecta incoerência antes da baixa', () {
      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: nomeRelogio,
          nomeExibido: nomeAnel,
        ),
        isTrue,
      );
    });

    test('expandirCombos ignora productId stale e resolve Anel pelo nome', () {
      final item = VendaItem(
        produtoNome: nomeAnel,
        quantidade: 1,
        precoUnitario: 99.0,
        lojaId: lojaId,
        productId: idRelogio,
      );

      final (itensExp, produtosEnc, _) = VendaComboEstoqueExpansion.expandirCombos(
        itens: [item],
        produtosBox: box,
        lojaId: lojaId,
      );

      expect(itensExp, hasLength(1));
      expect(produtosEnc, hasLength(1));
      expect(produtosEnc.single.nome, nomeAnel);
      expect(produtosEnc.single.idFirebase, idAnel);
      expect(produtosEnc.single.slug, slugAnel);
      expect(produtosEnc.single.slug, isNot(slugRelogio));
    });

    test('montarTxItemsParaBaixaEstoque não envia slug do Relógio', () {
      final item = VendaItem(
        produtoNome: nomeAnel,
        quantidade: 1,
        precoUnitario: 99.0,
        lojaId: lojaId,
        productId: idRelogio,
      );

      final (itensExp, produtosEnc, _) = VendaComboEstoqueExpansion.expandirCombos(
        itens: [item],
        produtosBox: box,
        lojaId: lojaId,
      );

      final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: itensExp,
        produtosEncontrados: produtosEnc,
      );

      expect(txItems, hasLength(1));
      final tx = txItems.single;
      expect(tx['nome'], nomeAnel);
      expect(tx['slug'], slugAnel);
      expect(tx['slug'], isNot(slugRelogio));
      expect(tx['productId'], idAnel);
      expect(tx['productId'], isNot(idRelogio));
    });

    test('sem guarda (productId coerente com Relógio) usaria slug errado — regressão', () {
      // Documenta o bug antigo: se não houvesse mismatch, resolveria Relógio pelo id.
      final relogio = box.values.firstWhere((p) => p.idFirebase == idRelogio);
      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: relogio.nome,
          nomeExibido: nomeAnel,
        ),
        isTrue,
        reason: 'Confirma que o cenário do cliente é incoerência real',
      );

      final itemStale = VendaItem(
        produtoNome: nomeAnel,
        quantidade: 1,
        precoUnitario: 99.0,
        lojaId: lojaId,
        productId: idRelogio,
      );

      // Simula comportamento pré-fix: resolver só por productId ignorando nome.
      final preFix = box.values.firstWhereOrNull(
        (prod) => prod.lojaId == lojaId && prod.idFirebase.trim() == idRelogio,
      );
      expect(preFix!.slug, slugRelogio);

      // Pós-fix: expandirCombos não usa preFix quando nome da linha é Anel.
      final (_, produtosEnc, __) = VendaComboEstoqueExpansion.expandirCombos(
        itens: [itemStale],
        produtosBox: box,
        lojaId: lojaId,
      );
      expect(produtosEnc.single.slug, isNot(preFix.slug));
    });
  });

  group('resolução segura quando nome não existe no estoque local', () {
    test('bloqueia com exceção se productId stale e nome não encontrado', () {
      final item = VendaItem(
        produtoNome: 'Produto Inexistente XYZ',
        quantidade: 1,
        precoUnitario: 10.0,
        lojaId: lojaId,
        productId: idRelogio,
      );

      expect(
        () => VendaComboEstoqueExpansion.expandirCombos(
          itens: [item],
          produtosBox: box,
          lojaId: lojaId,
        ),
        throwsA(
          predicate<Exception>(
            (e) => e.toString().contains('Produto Inexistente XYZ'),
          ),
        ),
      );
    });
  });

  group('nome ambíguo no estoque local', () {
    test('após ignorar productId stale, usa primeiro match por nome (risco documentado)', () async {
      await box.add(
        criar(
          nome: nomeAnel,
          idFirebase: 'produto-anel-duplicado',
          slug: 'anel-shine-regulavel-copia',
        ),
      );

      final item = VendaItem(
        produtoNome: nomeAnel,
        quantidade: 1,
        precoUnitario: 50.0,
        lojaId: lojaId,
        productId: idRelogio,
      );

      final (_, produtosEnc, __) = VendaComboEstoqueExpansion.expandirCombos(
        itens: [item],
        produtosBox: box,
        lojaId: lojaId,
      );

      expect(produtosEnc.single.nome.toLowerCase(), nomeAnel.toLowerCase());
      expect(produtosEnc.single.slug, isNot(slugRelogio));
    });
  });
}
