// M3.9 Sprint4-R4.1 — CLIENTE-PERM + ESTOQUE-PERM

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
import 'package:master_palm/core/produto_cadastro_gate.dart';
import 'package:master_palm/utils/role_utils.dart';

AccessScopeIdentity _seller() => AccessScopeIdentity(
      role: UserRole.vendedor,
      uid: 'v1',
      email: 'v1@t.com',
      displayName: 'Vendedor',
    );

AccessScopeIdentity _admin() => const AccessScopeIdentity(
      role: UserRole.admin,
      uid: 'a1',
      email: 'a@t.com',
      displayName: 'Admin',
    );

void main() {
  group('CLIENTE-PERM', () {
    test('CLIENTE-PERM-1 Vendedor não importa clientes', () {
      expect(AccessScopeService.canImportClients(_seller()), isFalse);
    });

    test('CLIENTE-PERM-2 Vendedor não abre importação (flag rota)', () {
      expect(AccessScopeService.canManageCustomers(_seller()), isFalse);
      expect(AccessScopeService.canImportClients(_seller()), isFalse);
    });

    test('CLIENTE-PERM-3 Vendedor não redefinesenha', () {
      expect(
        AccessScopeService.canResetClienteCatalogPassword(_seller()),
        isFalse,
      );
    });

    test('CLIENTE-PERM-4 Vendedor bloqueado em chamada direta (flag)', () {
      expect(AccessScopeService.canManageCustomers(_seller()), isFalse);
    });

    test('CLIENTE-PERM-5 Administrador mantém acesso', () {
      expect(AccessScopeService.canImportClients(_admin()), isTrue);
      expect(
        AccessScopeService.canResetClienteCatalogPassword(_admin()),
        isTrue,
      );
      expect(AccessScopeService.canManageCustomers(_admin()), isTrue);
    });
  });

  group('ESTOQUE-PERM', () {
    test('ESTOQUE-PERM-1 Vendedor não vê totais financeiros', () {
      expect(
        AccessScopeService.canSeeStockFinancialTotals(_seller()),
        isFalse,
      );
    });

    test('ESTOQUE-PERM-2 Vendedor não vê custo', () {
      expect(
        AccessScopeService.canSeeStockCostAndSupplier(_seller()),
        isFalse,
      );
    });

    test('ESTOQUE-PERM-3 Vendedor não vê indicadores financeiros', () {
      expect(AccessScopeService.canSeeFinancial(_seller()), isFalse);
      expect(
        AccessScopeService.canSeeStockFinancialTotals(_seller()),
        isFalse,
      );
    });

    test('ESTOQUE-PERM-4 Vendedor não gerencia/duplica produto', () {
      expect(AccessScopeService.canManageStock(_seller()), isFalse);
      expect(AccessScopeService.canEditStock(_seller()), isFalse);
      expect(podeAbrirCadastroProduto(_seller()), isFalse);
    });

    test('ESTOQUE-PERM-5 Ação direta de cadastro bloqueada', () {
      expect(podeAbrirCadastroProduto(_seller()), isFalse);
      expect(AccessScopeService.canManageStock(_seller()), isFalse);
    });

    test('ESTOQUE-PERM-6 Menu admin exige canManageStock', () {
      expect(AccessScopeService.canManageStock(_seller()), isFalse);
      expect(AccessScopeService.canConsultStock(_seller()), isTrue);
    });

    test('ESTOQUE-PERM-7 Rotas administrativas bloqueadas (flag)', () {
      expect(AccessScopeService.canManageStock(_seller()), isFalse);
      expect(AccessScopeService.canEditStock(_seller()), isFalse);
    });

    test('ESTOQUE-PERM-8 Administrador mantém acesso completo', () {
      expect(AccessScopeService.canManageStock(_admin()), isTrue);
      expect(AccessScopeService.canSeeStockFinancialTotals(_admin()), isTrue);
      expect(AccessScopeService.canSeeStockCostAndSupplier(_admin()), isTrue);
      expect(podeAbrirCadastroProduto(_admin()), isTrue);
    });
  });
}
