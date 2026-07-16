// M3.9 SPRINT4-R2.1 — PRODUTO-1..10 (estoque zero + cadastro bloqueado)

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
  Map<String, int>? estoquePorTamanho,
}) {
  return Produto.vazio()
    ..nome = nome
    ..idFirebase = id
    ..lojaId = 'loja-r21'
    ..quantidade = qtd
    ..ativoNoRascunho = true
    ..precoFinal = 10
    ..codigoBarras = barcode
    ..sku = barcode
    ..estoquePorTamanho = Map<String, int>.from(estoquePorTamanho ?? {});
}

void main() {
  group('PRODUTO estoque zero + cadastro', () {
    test('PRODUTO-1 Produto estoque 0 não aparece', () {
      expect(
        produtoEstoqueDisponivelParaVendedor(
          _prod(id: 'z', nome: 'Zerado', qtd: 0),
        ),
        isFalse,
      );
    });

    test('PRODUTO-2 Ao zerar estoque desaparece automaticamente', () {
      final p = _prod(id: 'x', nome: 'Anel', qtd: 2);
      expect(produtoEstoqueDisponivelParaVendedor(p), isTrue);
      p.quantidade = 0;
      expect(produtoEstoqueDisponivelParaVendedor(p), isFalse);
    });

    test('PRODUTO-3 Pesquisa por código de barras não retorna produto zerado', () {
      final produtos = [
        _prod(id: 'a', nome: 'A', qtd: 0, barcode: '7891000100103'),
        _prod(id: 'b', nome: 'B', qtd: 3, barcode: '7891000100104'),
      ];
      final q = '7891000100103';
      final hit = produtos
          .where(produtoEstoqueDisponivelParaVendedor)
          .where((p) =>
              p.codigoBarras.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q))
          .toList();
      expect(hit, isEmpty);
      final ok = produtos
          .where(produtoEstoqueDisponivelParaVendedor)
          .where((p) => p.codigoBarras.contains('7891000100104'))
          .toList();
      expect(ok.map((e) => e.idFirebase), ['b']);
    });

    test('PRODUTO-4 Pesquisa por nome não retorna produto zerado', () {
      final produtos = [
        _prod(id: '1', nome: 'Anel Ouro', qtd: 0),
        _prod(id: '2', nome: 'Anel Prata', qtd: 1),
      ];
      final list = produtos
          .where(produtoEstoqueDisponivelParaVendedor)
          .where((p) => p.nome.toLowerCase().contains('anel'))
          .toList();
      expect(list.map((e) => e.idFirebase), ['2']);
    });

    test('PRODUTO-5 Administrador continua vendo produto zerado', () {
      // Admin não usa o filtro de estoque zero na listagem de cadastro.
      expect(AccessScopeService.canManageStock(_admin()), isTrue);
      expect(
        produtoEstoqueDisponivelParaVendedor(
          _prod(id: 'z', nome: 'Zerado', qtd: 0),
        ),
        isFalse,
      );
      // Flag de cadastro permite admin abrir/editar mesmo zerado.
      expect(podeAbrirCadastroProduto(_admin()), isTrue);
    });

    test('PRODUTO-6 Vendedor não consegue abrir tela de edição', () {
      expect(podeAbrirCadastroProduto(_seller('v1')), isFalse);
      expect(AccessScopeService.canManageStock(_seller('v1')), isFalse);
      expect(AccessScopeService.canEditStock(_seller('v1')), isFalse);
    });

    test('PRODUTO-7 Acesso direto por rota é bloqueado (flag)', () {
      expect(podeAbrirCadastroProduto(_seller('x')), isFalse);
      expect(podeAbrirCadastroProduto(_admin()), isTrue);
      expect(
        kProdutoCadastroDeniedMessage,
        contains('permissão para editar produtos'),
      );
    });

    test('PRODUTO-8 Botão editar oculto (canEditStock)', () {
      expect(AccessScopeService.canEditStock(_seller('v')), isFalse);
      expect(AccessScopeService.canEditStock(_admin()), isTrue);
    });

    test('PRODUTO-9 Botão novo produto oculto (canManageStock)', () {
      expect(AccessScopeService.canManageStock(_seller('v')), isFalse);
      expect(AccessScopeService.canManageStock(_admin()), isTrue);
    });

    test('PRODUTO-10 Botão excluir oculto (canManageStock)', () {
      expect(AccessScopeService.canManageStock(_seller('v')), isFalse);
      expect(AccessScopeService.canSeeStockCostAndSupplier(_seller('v')), isFalse);
      expect(AccessScopeService.canConsultStock(_seller('v')), isTrue);
      expect(AccessScopeService.canSeeStockCostAndSupplier(_admin()), isTrue);
    });
  });
}
