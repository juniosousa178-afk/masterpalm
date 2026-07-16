// M3.9 SPRINT4-R2 — AccessScope + hotfix Vendas (escopo publicável)

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
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

void main() {
  group('GESTAO-R2 escopo global', () {
    test('GESTAO-R2-1 vendedor não vê resumo global', () {
      expect(
        AccessScopeService.canSeeVendasResumoGlobal(_seller('v1')),
        isFalse,
      );
    });

    test('GESTAO-R2-hotfix vendedor acessa tela Vendas; sem KPIs de loja', () {
      final s = _seller('v1');
      expect(AccessScopeService.canAccessVendasScreen(s), isTrue);
      expect(AccessScopeService.canSeeVendasStoreKpis(s), isFalse);
      expect(AccessScopeService.canSeeStoreAggregates(s), isFalse);
      expect(AccessScopeService.canAccessVendasScreen(_admin()), isTrue);
      expect(AccessScopeService.canSeeVendasStoreKpis(_admin()), isTrue);
    });

    test('GESTAO-R2-2 vendedor não acessa mais vendidos', () {
      expect(AccessScopeService.canSeeMaisVendidos(_seller('v1')), isFalse);
    });

    test('GESTAO-R2-3 admin mantém resumo e mais vendidos', () {
      expect(AccessScopeService.canSeeVendasResumoGlobal(_admin()), isTrue);
      expect(AccessScopeService.canSeeMaisVendidos(_admin()), isTrue);
      expect(AccessScopeService.canSeeFinanceiroMetasLoja(_admin()), isTrue);
    });

    test('GESTAO-R2-22 rota direta não vaza agregados (flags)', () {
      expect(AccessScopeService.canSeeStoreAggregates(_seller('x')), isFalse);
      expect(AccessScopeService.canSeeVendasResumoGlobal(_seller('x')), isFalse);
      expect(AccessScopeService.canSeeMaisVendidos(_seller('x')), isFalse);
      expect(AccessScopeService.canSeeFinanceiroMetasLoja(_seller('x')), isFalse);
      expect(AccessScopeService.canSeeStockFinancialTotals(_seller('x')), isFalse);
    });

    test('GESTAO-R2-25 admin vê tudo normalmente', () {
      expect(AccessScopeService.canSeeStoreAggregates(_admin()), isTrue);
      expect(AccessScopeService.canSeeStockFinancialTotals(_admin()), isTrue);
    });

    test('GESTAO-R2-14 vendedor não vê totais financeiros estoque', () {
      expect(
        AccessScopeService.canSeeStockFinancialTotals(_seller('v')),
        isFalse,
      );
    });
  });
}
