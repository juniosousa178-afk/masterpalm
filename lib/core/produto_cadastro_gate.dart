// Gate único de cadastro/edição de produtos (Sprint4-R2.1).

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/produto.dart';
import '../services/store_membership_authz_service.dart';
import 'access_scope_service.dart';
import 'loja_id_adapter.dart';
import 'store_membership_authz.dart';

const kProdutoCadastroDeniedMessage =
    'Você não possui permissão para editar produtos.';

/// Sync check: global privileged OR explicit membership snapshot.
bool podeAbrirCadastroProduto(
  AccessScopeIdentity id, {
  StoreMembershipSnapshot? storeMembership,
  String? currentStoreId,
}) =>
    AccessScopeService.canManageStock(
      id,
      storeMembership: storeMembership,
      currentStoreId: currentStoreId,
    );

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

Future<String?> _currentStoreIdFromSession() async {
  try {
    final sessao = Hive.isBoxOpen('sessao')
        ? Hive.box('sessao')
        : await Hive.openBox('sessao');
    return normalizeFromBox(sessao)?.trim();
  } catch (_) {
    return null;
  }
}

/// Resolves membership for [storeId] (session fallback) then evaluates capability.
Future<bool> resolveProdutoCadastroAccess({
  AccessScopeIdentity? identity,
  String? storeId,
  StoreMembershipAuthzService? membershipService,
}) async {
  final id = identity ?? await AccessScopeService.loadIdentity();
  if (id.isAdmin) return true;

  final loja = (storeId ?? await _currentStoreIdFromSession() ?? '').trim();
  if (loja.isEmpty || id.uid.trim().isEmpty) return false;

  final svc = membershipService ?? sharedStoreMembershipAuthz();
  final snap = await svc.fetchOnce(storeId: loja, uid: id.uid);
  return AccessScopeService.canManageStock(
    id,
    storeMembership: snap,
    currentStoreId: loja,
  );
}

/// Snackbar + false se vendedor/sem permissão.
Future<bool> ensureProdutoCadastroAccess(BuildContext context) async {
  final ok = await resolveProdutoCadastroAccess();
  if (ok) return true;
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
