// Gate único de cadastro/edição de produtos (Sprint4-R2.1).

import 'package:flutter/material.dart';

import '../models/produto.dart';
import 'access_scope_service.dart';

const kProdutoCadastroDeniedMessage =
    'Você não possui permissão para editar produtos.';

/// Acesso a formulários de cadastro/edição (produto avulso, kit, inventário).
bool podeAbrirCadastroProduto(AccessScopeIdentity id) =>
    AccessScopeService.canManageStock(id);

/// Estoque disponível para listagem do vendedor (sem deps de gestão comercial).
bool produtoEstoqueDisponivelParaVendedor(Produto p) {
  if (p.estoquePorTamanho.isNotEmpty) {
    return p.estoquePorTamanho.values.any((q) => q > 0);
  }
  final vars = p.variacoes;
  if (vars != null && vars.isNotEmpty) {
    var sum = 0;
    for (final corMap in vars.values) {
      if (corMap is! Map) continue;
      for (final v in corMap.values) {
        if (v is int) {
          if (v > 0) sum += v;
        } else if (v is Map) {
          for (final q in v.values) {
            if (q is int && q > 0) sum += q;
          }
        }
      }
    }
    return sum > 0;
  }
  return p.quantidade > 0;
}

/// Snackbar + false se vendedor/sem permissão.
Future<bool> ensureProdutoCadastroAccess(BuildContext context) async {
  final id = await AccessScopeService.loadIdentity();
  if (podeAbrirCadastroProduto(id)) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(kProdutoCadastroDeniedMessage)),
    );
  }
  return false;
}

/// Usado em initState de formulários: bloqueia e faz pop se não autorizado.
Future<void> enforceProdutoCadastroOrPop(BuildContext context) async {
  final ok = await ensureProdutoCadastroAccess(context);
  if (!ok && context.mounted) {
    Navigator.of(context).maybePop();
  }
}
