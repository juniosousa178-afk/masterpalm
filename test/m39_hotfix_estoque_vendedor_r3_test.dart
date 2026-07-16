// M3.9-HOTFIX-ESTOQUE-VENDEDOR-R3 — ESTOQUE-R3-1..5
// Fonte alinhada ao Catálogo Interno: produtoEstoqueDisponivelParaVendedor.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
import 'package:master_palm/core/produto_cadastro_gate.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/utils/role_utils.dart';

AccessScopeIdentity _seller(String uid) => AccessScopeIdentity(
      role: UserRole.vendedor,
      uid: uid,
      email: '$uid@t.com',
      displayName: uid,
    );

AccessScopeIdentity _admin() => const AccessScopeIdentity(
      role: UserRole.admin,
      uid: 'admin-1',
      email: 'a@t.com',
      displayName: 'Admin',
    );

Produto _prod({
  required String id,
  required String nome,
  int qtd = 5,
  String barcode = '',
  String categoria = 'Aneis',
  String sku = '',
}) {
  return Produto.vazio()
    ..nome = nome
    ..idFirebase = id
    ..lojaId = 'loja-r3'
    ..quantidade = qtd
    ..ativoNoRascunho = true
    ..precoFinal = 10
    ..codigoBarras = barcode
    ..sku = sku.isNotEmpty ? sku : barcode
    ..categoria = categoria;
}

/// Espelha listagem Estoque: base canónica + busca/categoria (vendedor).
List<Produto> _listagemEstoque({
  required AccessScopeIdentity scope,
  required Iterable<Produto> produtos,
  String query = '',
  String? categoria,
}) {
  final isSeller = scope.isSeller;
  var list = produtos.where((p) {
    if (!isSeller) return true;
    return produtoEstoqueDisponivelParaVendedor(p);
  }).toList();
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    list = list.where((p) {
      final sku = (p.codigoBarras.isNotEmpty ? p.codigoBarras : p.sku)
          .toLowerCase();
      return p.nome.toLowerCase().contains(q) ||
          p.categoria.toLowerCase().contains(q) ||
          p.subcategoria.toLowerCase().contains(q) ||
          sku.contains(q);
    }).toList();
  }
  if (categoria != null && categoria.isNotEmpty) {
    list = list
        .where((p) =>
            p.categoria.trim().toLowerCase() == categoria.trim().toLowerCase())
        .toList();
  }
  return list;
}

void main() {
  group('ESTOQUE-R3 vendedor = fonte catálogo', () {
    test('ESTOQUE-R3-1 Produto estoque zero não aparece', () {
      final list = _listagemEstoque(
        scope: _seller('v1'),
        produtos: [
          _prod(id: 'z', nome: 'Zerado', qtd: 0),
          _prod(id: 'ok', nome: 'Ok', qtd: 2),
        ],
      );
      expect(list.map((e) => e.idFirebase), ['ok']);
      expect(
        produtoEstoqueDisponivelParaVendedor(
          _prod(id: 'z', nome: 'Zerado', qtd: 0),
        ),
        isFalse,
      );
    });

    test('ESTOQUE-R3-2 Ao zerar estoque desaparece automaticamente', () {
      final p = _prod(id: 'x', nome: 'Anel', qtd: 3);
      expect(
        _listagemEstoque(scope: _seller('v1'), produtos: [p])
            .map((e) => e.idFirebase),
        ['x'],
      );
      p.quantidade = 0;
      expect(produtoEstoqueDisponivelParaVendedor(p), isFalse);
      expect(
        _listagemEstoque(scope: _seller('v1'), produtos: [p]),
        isEmpty,
      );
    });

    test('ESTOQUE-R3-3 Pesquisa não encontra produto zerado', () {
      final produtos = [
        _prod(id: 'a', nome: 'Anel Ouro', qtd: 0, barcode: '7891000100103'),
        _prod(id: 'b', nome: 'Anel Prata', qtd: 4, barcode: '7891000100104'),
      ];
      expect(
        _listagemEstoque(
          scope: _seller('v1'),
          produtos: produtos,
          query: 'anel ouro',
        ),
        isEmpty,
      );
      expect(
        _listagemEstoque(
          scope: _seller('v1'),
          produtos: produtos,
          query: '7891000100103',
        ),
        isEmpty,
      );
      expect(
        _listagemEstoque(
          scope: _seller('v1'),
          produtos: produtos,
          query: 'anel',
        ).map((e) => e.idFirebase),
        ['b'],
      );
      expect(
        _listagemEstoque(
          scope: _seller('v1'),
          produtos: produtos,
          query: '7891000100104',
        ).map((e) => e.idFirebase),
        ['b'],
      );
    });

    test('ESTOQUE-R3-4 Categoria não mostra produto zerado', () {
      final list = _listagemEstoque(
        scope: _seller('v1'),
        produtos: [
          _prod(id: 'z', nome: 'Zerado', qtd: 0, categoria: 'Aneis'),
          _prod(id: 'ok', nome: 'Ok', qtd: 1, categoria: 'Aneis'),
          _prod(id: 'out', nome: 'Outro', qtd: 5, categoria: 'Brincos'),
        ],
        categoria: 'Aneis',
      );
      expect(list.map((e) => e.idFirebase), ['ok']);
    });

    test('ESTOQUE-R3-5 Administrador continua vendo todos', () {
      final produtos = [
        _prod(id: 'z', nome: 'Zerado', qtd: 0),
        _prod(id: 'ok', nome: 'Ok', qtd: 2),
      ];
      final admin = _listagemEstoque(scope: _admin(), produtos: produtos);
      expect(admin.map((e) => e.idFirebase).toList()..sort(), ['ok', 'z']);
      expect(AccessScopeService.canManageStock(_admin()), isTrue);
    });
  });
}
