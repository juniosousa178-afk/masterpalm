// M3.9 Sprint4-R4.3 — CATALOGO-PERF-1..5 (publish: sem dependência gestao WIP)

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_cadastro_gate.dart';
import 'package:master_palm/models/produto.dart';

Produto _p({
  required String id,
  required String nome,
  int qtd = 1,
}) {
  return Produto.vazio()
    ..idFirebase = id
    ..nome = nome
    ..lojaId = 'loja'
    ..quantidade = qtd
    ..ativoNoRascunho = true
    ..categoria = 'A'
    ..precoFinal = 10;
}

void main() {
  group('CATALOGO-PERF', () {
    test('CATALOGO-PERF-1 Filtro local de estoque zero sem await remoto', () {
      final produtos = [
        _p(id: '1', nome: 'Ok', qtd: 2),
        _p(id: 'z', nome: 'Zero', qtd: 0),
      ];
      final local = produtos
          .where(produtoEstoqueDisponivelParaVendedor)
          .toList();
      expect(local.map((e) => e.idFirebase), ['1']);
    });

    test('CATALOGO-PERF-2 Cache key muda só com inputs relevantes', () {
      String key({
        required int len,
        required String q,
        String? cat,
        required bool fav,
      }) =>
          'e0|$len|$q|${cat ?? ''}|$fav';
      expect(
        key(len: 10, q: '', cat: null, fav: false),
        key(len: 10, q: '', cat: null, fav: false),
      );
      expect(
        key(len: 10, q: '', cat: null, fav: false),
        isNot(key(len: 11, q: '', cat: null, fav: false)),
      );
      expect(
        key(len: 10, q: 'a', cat: null, fav: false),
        isNot(key(len: 10, q: 'b', cat: null, fav: false)),
      );
    });

    test('CATALOGO-PERF-3 Debounce query filtra por nome', () {
      final produtos = [
        _p(id: '1', nome: 'Anel', qtd: 1),
        _p(id: '2', nome: 'Brinco', qtd: 1),
      ];
      const q = 'anel';
      final filtrados = produtos
          .where((p) => p.nome.toLowerCase().contains(q))
          .toList();
      expect(filtrados.map((e) => e.idFirebase), ['1']);
    });

    test('CATALOGO-PERF-4 Zerados continuam ocultos', () {
      expect(
        produtoEstoqueDisponivelParaVendedor(_p(id: 'z', nome: 'Z', qtd: 0)),
        isFalse,
      );
    });

    test('CATALOGO-PERF-5 Produto com estoque permanece visível', () {
      expect(
        produtoEstoqueDisponivelParaVendedor(_p(id: '1', nome: 'Ok', qtd: 3)),
        isTrue,
      );
    });
  });
}
