import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/services/estoque_service.dart';

const _lojaId = 'loja-entrada-forn-test';

Produto _produtoSimples() {
  return Produto(
    nome: 'Colar Novo',
    custoReal: 15,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 60,
    quantidade: 0,
    precoUnitario: 60,
    categoria: 'Colar',
    dataEntrada: DateTime(2026, 6, 9),
    lojaId: _lojaId,
    idFirebase: 'colar-novo-id',
    slug: 'colar-novo-id',
  );
}

void main() {
  group('Entrada fornecedor — cria e persiste variações no produto', () {
    late Box<Produto> box;
    late Directory hiveDir;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('entrada_forn_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    setUp(() async {
      final name = HiveBoxNames.produtos(_lojaId);
      if (Hive.isBoxOpen(name)) await Hive.box<Produto>(name).close();
      box = await Hive.openBox<Produto>(name);
      await box.clear();
    });

    tearDown(() async {
      if (box.isOpen) await box.close();
    });

    tearDownAll(() async {
      await Hive.close();
    });

    test('entrada em produto simples soma quantidade total', () async {
      final p = _produtoSimples();
      await box.add(p);

      final r = await EstoqueService.atualizarEstoque(
        produtosBox: box,
        lojaId: _lojaId,
        produtoId: p.idFirebase,
        tamanho: '',
        cor: '',
        quantidade: 5,
        operacao: 'entrada_compra',
      );

      expect(r.sucesso, isTrue);
      expect(r.estoqueDepois, 5);
      expect(p.quantidade, 5);
    });

    test('entrada com cor em produto simples cria variacoes sem-tamanho', () async {
      final p = _produtoSimples();
      await box.add(p);

      final r = await EstoqueService.atualizarEstoque(
        produtosBox: box,
        lojaId: _lojaId,
        produtoId: p.idFirebase,
        tamanho: '',
        cor: 'Rose',
        quantidade: 3,
        operacao: 'entrada_compra',
      );

      expect(r.sucesso, isTrue);
      expect(p.usaVariacoes, isTrue);
      expect(
        ProdutoVariacaoExtra.somarCelula(p.variacoes?['sem-tamanho']?['Rose']),
        3,
      );
      expect(p.quantidade, 3);
    });

    test('entrada tamanho+cor soma combinação correta', () async {
      final p = _produtoSimples()
        ..variacoes = {
          'P': {'Azul': 1},
        }
        ..quantidade = 1;
      await box.add(p);

      final r = await EstoqueService.atualizarEstoque(
        produtosBox: box,
        lojaId: _lojaId,
        produtoId: p.idFirebase,
        tamanho: 'P',
        cor: 'Azul',
        quantidade: 2,
        operacao: 'entrada_compra',
      );

      expect(r.sucesso, isTrue);
      expect(
        ProdutoVariacaoExtra.somarCelula(p.variacoes?['P']?['Azul']),
        3,
      );
      expect(p.quantidade, 3);
    });
  });
}
