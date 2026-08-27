// SALE_EDIT_STOCK_002 — identidade ID-first após rename; Lavile preservado.
// Sem loja real / sem escrita de produção.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/strict_product_resolution.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';
import 'package:master_palm/services/venda_edicao_estoque_diff.dart';
import 'package:master_palm/services/vendas_service.dart';

const kOldName = 'Duplinha Argola Torcida Prata 925';
const kNewName = 'Brinco Duplinha Argola Torcida Prata 925';
const kPid = 'p-argola-1';
const kLoja = 'loja-sale-edit-stock-002';

void main() {
  group('decideProdutoLinhaIdentity', () {
    test('CASE A: mesmo ID e nome actual → useId', () {
      expect(
        decideProdutoLinhaIdentity(
          hasIdCandidate: true,
          hasNameCandidate: true,
          idCandidateNameAgreesWithLine: true,
          idAndNameAreSameProduct: true,
        ),
        ProdutoLinhaIdentityChoice.useIdCandidate,
      );
    });

    test('CASE B: rename — ID existe, nome da linha não casa outro produto → useId', () {
      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: kNewName,
          nomeExibido: kOldName,
        ),
        isTrue,
      );
      expect(
        decideProdutoLinhaIdentity(
          hasIdCandidate: true,
          hasNameCandidate: false,
          idCandidateNameAgreesWithLine: false,
          idAndNameAreSameProduct: false,
        ),
        ProdutoLinhaIdentityChoice.useIdCandidate,
      );
    });

    test('CASE C Lavile: ID=A, nome único=B distinto → useName', () {
      expect(
        decideProdutoLinhaIdentity(
          hasIdCandidate: true,
          hasNameCandidate: true,
          idCandidateNameAgreesWithLine: false,
          idAndNameAreSameProduct: false,
        ),
        ProdutoLinhaIdentityChoice.useNameCandidate,
      );
    });

    test('CASE D: sem ID, nome único → useName', () {
      expect(
        decideProdutoLinhaIdentity(
          hasIdCandidate: false,
          hasNameCandidate: true,
          idCandidateNameAgreesWithLine: false,
          idAndNameAreSameProduct: false,
        ),
        ProdutoLinhaIdentityChoice.useNameCandidate,
      );
    });

    test('CASE E: ID e nome ausentes → notFound', () {
      expect(
        decideProdutoLinhaIdentity(
          hasIdCandidate: false,
          hasNameCandidate: false,
          idCandidateNameAgreesWithLine: false,
          idAndNameAreSameProduct: false,
        ),
        ProdutoLinhaIdentityChoice.notFound,
      );
    });
  });

  group('Hive: rename + delta (sem alterar fórmula de estoque)', () {
    late String hivePath;
    late Box<Produto> produtosBox;

    Produto argola({required String nome, int qtd = 0}) {
      final p = Produto.vazio();
      p.nome = nome;
      p.idFirebase = kPid;
      p.lojaId = kLoja;
      p.quantidade = qtd;
      p.precoFinal = 50;
      return p;
    }

    Venda vendaCom(List<VendaItem> itens) {
      return Venda(
        clienteNome: 'Cliente',
        produtosDescricao: '',
        quantidade: itens.fold<int>(0, (a, i) => a + i.quantidade),
        preco: 50,
        total: 50,
        formasPagamento: 'Pix',
        data: DateTime(2026, 8, 26),
        tamanho: '',
        vendedor: 'App',
        observacao: '',
        itens: itens,
        lojaId: kLoja,
      );
    }

    VendaItem linha({required String nome, required int qtd, String? productId}) {
      return VendaItem(
        produtoNome: nome,
        quantidade: qtd,
        precoUnitario: 50,
        productId: productId,
        lojaId: kLoja,
      );
    }

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_ses002_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
      if (!Hive.isAdapterRegistered(7)) {
        Hive.registerAdapter(VendaItemAdapter());
      }
    });

    setUp(() async {
      setStrictResolutionTestOverride(false);
      produtosBox = await Hive.openBox<Produto>(
        'prod_ses002_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      setStrictResolutionTestOverride(null);
      await produtosBox.close();
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    test('RENAME_SAME_ID: qty 1, stock 0, resolve P1 e delta 0', () async {
      await produtosBox.add(argola(nome: kNewName, qtd: 0));
      final original = vendaCom([
        linha(nome: kOldName, qtd: 1, productId: kPid),
      ]);
      final novos = [
        linha(nome: kOldName, qtd: 1, productId: kPid),
      ];

      final byId = produtosBox.values.firstWhere(
        (p) => p.lojaId == kLoja && p.idFirebase == kPid,
      );
      final byName = produtosBox.values.cast<Produto?>().firstWhere(
            (p) =>
                p!.lojaId == kLoja &&
                p.nome.trim().toLowerCase() == kOldName.trim().toLowerCase(),
            orElse: () => null,
          );
      expect(
        decideProdutoLinhaIdentity(
          hasIdCandidate: byId.nome.isNotEmpty,
          hasNameCandidate: byName != null,
          idCandidateNameAgreesWithLine: !productIdIncoerenteComNomeExibido(
            nomeProdutoResolvido: byId.nome,
            nomeExibido: kOldName,
          ),
          idAndNameAreSameProduct: false,
        ),
        ProdutoLinhaIdentityChoice.useIdCandidate,
      );

      final (exp, prods, _) = VendaComboEstoqueExpansion.expandirCombos(
        itens: novos,
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(prods.single.idFirebase, kPid);
      expect(exp.single.quantidade, 1);

      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: novos,
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(pre.pularValidacaoEstoque, isTrue);
      expect(pre.linhasValidarBaixa, isEmpty);
    });

    test('SAME_ID_CURRENT_NAME: nome actual → P1', () async {
      await produtosBox.add(argola(nome: kNewName, qtd: 1));
      final expanded = VendaComboEstoqueExpansion.expandirCombos(
        itens: [linha(nome: kNewName, qtd: 1, productId: kPid)],
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(expanded.$2.single.idFirebase, kPid);
      expect(expanded.$2.single.nome, kNewName);
    });

    test('LAVILE_WRONG_ID: ID relógio + nome anel → anel', () async {
      final relogio = Produto.vazio()
        ..nome = 'Relógio Cássio Oval'
        ..idFirebase = 'produto-relogio'
        ..lojaId = kLoja
        ..quantidade = 2;
      final anel = Produto.vazio()
        ..nome = 'Anel Shine Regulável'
        ..idFirebase = 'produto-anel'
        ..lojaId = kLoja
        ..quantidade = 2;
      await produtosBox.addAll([relogio, anel]);

      final expanded = VendaComboEstoqueExpansion.expandirCombos(
        itens: [
          linha(
            nome: 'Anel Shine Regulável',
            qtd: 1,
            productId: 'produto-relogio',
          ),
        ],
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(expanded.$2.single.idFirebase, 'produto-anel');
    });

    test('LEGACY_NAME_FALLBACK: sem productId, nome actual → P1', () async {
      await produtosBox.add(argola(nome: kNewName, qtd: 3));
      final expanded = VendaComboEstoqueExpansion.expandirCombos(
        itens: [linha(nome: kNewName, qtd: 1, productId: null)],
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(expanded.$2.single.idFirebase, kPid);
    });

    test('REAL_REMOVED_PRODUCT: ID e nome inexistentes → not found', () {
      expect(
        () => VendaComboEstoqueExpansion.expandirCombos(
          itens: [
            linha(nome: kOldName, qtd: 1, productId: 'gone'),
          ],
          produtosBox: produtosBox,
          lojaId: kLoja,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('RENAME_QTY_INCREASE_AVAILABLE: delta baixa = 1', () async {
      await produtosBox.add(argola(nome: kNewName, qtd: 1));
      final original = vendaCom([
        linha(nome: kOldName, qtd: 1, productId: kPid),
      ]);
      final novos = [
        linha(nome: kOldName, qtd: 2, productId: kPid),
      ];
      final expanded = VendaComboEstoqueExpansion.expandirCombos(
        itens: novos,
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(expanded.$2.single.idFirebase, kPid);
      expect(expanded.$2.single.quantidade, 1);

      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: novos,
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(pre.pularValidacaoEstoque, isFalse);
      expect(pre.linhasValidarBaixa.single['quantidade'], 1);
    });

    test('RENAME_TRUE_INSUFFICIENT_STOCK: resolve P1; extra qty 1 com stock 0', () async {
      await produtosBox.add(argola(nome: kNewName, qtd: 0));
      final original = vendaCom([
        linha(nome: kOldName, qtd: 1, productId: kPid),
      ]);
      final novos = [
        linha(nome: kOldName, qtd: 2, productId: kPid),
      ];
      final expanded = VendaComboEstoqueExpansion.expandirCombos(
        itens: novos,
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(expanded.$2.single.idFirebase, kPid);
      expect(expanded.$2.single.quantidade, 0);

      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: novos,
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      expect(pre.linhasValidarBaixa.single['quantidade'], 1);
      expect(
        expanded.$2.single.quantidade <
            (pre.linhasValidarBaixa.single['quantidade'] as int),
        isTrue,
      );
    });

    test('RENAME_QTY_DECREASE: delta devolve 1', () async {
      await produtosBox.add(argola(nome: kNewName, qtd: 0));
      final linhasAntigas = VendasService.montarLinhasEstoqueCanonicasParaEdicao(
        itens: [linha(nome: kOldName, qtd: 2, productId: kPid)],
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      final linhasNovas = VendasService.montarLinhasEstoqueCanonicasParaEdicao(
        itens: [linha(nome: kOldName, qtd: 1, productId: kPid)],
        produtosBox: produtosBox,
        lojaId: kLoja,
      );
      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: linhasAntigas,
        linhasNovas: linhasNovas,
      );
      expect(delta.baixar, isEmpty);
      expect(delta.devolver.single['quantidade'], 1);
    });

    test('produto de outra loja não é aceite pelo mesmo productId', () async {
      final outro = argola(nome: kNewName, qtd: 9)..lojaId = 'outra-loja';
      await produtosBox.add(outro);
      expect(
        () => VendaComboEstoqueExpansion.expandirCombos(
          itens: [linha(nome: kOldName, qtd: 1, productId: kPid)],
          produtosBox: produtosBox,
          lojaId: kLoja,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
