// M3.8 SPRINT3-MULTIUSUARIO-R1 — testes MULTI-1…10

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/utils/role_utils.dart';

Venda _v({
  required String cliente,
  required String vendedor,
  String loja = 'loja-1',
  double total = 100,
  String? clienteId,
}) {
  return Venda(
    preco: total,
    produtosDescricao: 'Item',
    quantidade: 1,
    clienteNome: cliente,
    total: total,
    formasPagamento: 'pix',
    data: DateTime(2026, 7, 1),
    tamanho: '',
    desconto: 0,
    frete: 0,
    vendedor: vendedor,
    observacao: '',
    lojaId: loja,
    clienteId: clienteId,
  );
}

AccessScopeIdentity _admin() => const AccessScopeIdentity(
      role: UserRole.admin,
      uid: 'admin-uid',
      email: 'admin@loja.com',
      displayName: 'Admin',
    );

AccessScopeIdentity _sellerPedro() => const AccessScopeIdentity(
      role: UserRole.vendedor,
      uid: 'pedro-uid',
      email: 'pedro@loja.com',
      displayName: 'Pedro',
    );

AccessScopeIdentity _sellerMaria() => const AccessScopeIdentity(
      role: UserRole.vendedor,
      uid: 'maria-uid',
      email: 'maria@loja.com',
      displayName: 'Maria',
    );

void main() {
  group('MULTI', () {
    final vendas = [
      _v(cliente: 'João', vendedor: 'pedro@loja.com', clienteId: 'c-joao'),
      _v(cliente: 'João', vendedor: 'maria@loja.com', clienteId: 'c-joao'),
      _v(cliente: 'João', vendedor: 'pedro@loja.com', clienteId: 'c-joao'),
      _v(cliente: 'Ana', vendedor: 'maria@loja.com', clienteId: 'c-ana'),
    ];

    test('MULTI-1 Admin vê todas vendas', () {
      final filtered = AccessScopeService.filterSalesForScope(
        id: _admin(),
        sales: vendas,
        lojaId: 'loja-1',
      );
      expect(filtered.length, 4);
    });

    test('MULTI-2 Vendedor vê apenas suas vendas', () {
      final pedro = AccessScopeService.filterSalesForScope(
        id: _sellerPedro(),
        sales: vendas,
        lojaId: 'loja-1',
      );
      expect(pedro.length, 2);
      expect(pedro.every((v) => v.vendedor == 'pedro@loja.com'), isTrue);

      final maria = AccessScopeService.filterSalesForScope(
        id: _sellerMaria(),
        sales: vendas,
        lojaId: 'loja-1',
      );
      expect(maria.length, 2);
      expect(maria.every((v) => v.vendedor == 'maria@loja.com'), isTrue);
    });

    test('MULTI-3 Cliente aparece na pesquisa global (Nova Venda)', () {
      expect(
        AccessScopeService.canSearchAllCustomersInSale(_sellerPedro()),
        isTrue,
      );
      expect(
        AccessScopeService.canSearchAllCustomersInSale(_admin()),
        isTrue,
      );
    });

    test('MULTI-4 Cliente não aparece na lista antes da primeira venda', () {
      final wallet = AccessScopeService.buildSellerWalletKeys(
        id: _sellerPedro(),
        sales: vendas,
        lojaId: 'loja-1',
      );
      expect(
        AccessScopeService.canSeeCustomerInList(
          id: _sellerPedro(),
          customerKey: 'Cliente Novo',
          walletCustomerKeys: wallet,
        ),
        isFalse,
      );
    });

    test('MULTI-5 Após vender, cliente entra na carteira', () {
      final wallet = AccessScopeService.buildSellerWalletKeys(
        id: _sellerPedro(),
        sales: vendas,
        lojaId: 'loja-1',
      );
      expect(wallet.contains('joão') || wallet.contains('c-joao'), isTrue);
      expect(
        AccessScopeService.customerBelongsToSeller(
          id: _sellerPedro(),
          customerKey: 'João',
          walletCustomerKeys: wallet,
        ),
        isTrue,
      );
      expect(
        AccessScopeService.customerBelongsToSeller(
          id: _sellerPedro(),
          customerKey: 'Ana',
          walletCustomerKeys: wallet,
        ),
        isFalse,
      );
    });

    test('MULTI-6 Histórico mostra apenas vendas próprias', () {
      final hist = AccessScopeService.filterCustomerHistory(
        id: _sellerPedro(),
        sales: vendas,
        lojaId: 'loja-1',
        customerName: 'João',
        customerId: 'c-joao',
      );
      expect(hist.length, 2);
      expect(hist.every((v) => v.vendedor == 'pedro@loja.com'), isTrue);

      final histMaria = AccessScopeService.filterCustomerHistory(
        id: _sellerMaria(),
        sales: vendas,
        lojaId: 'loja-1',
        customerName: 'João',
      );
      expect(histMaria.length, 1);
      expect(histMaria.first.vendedor, 'maria@loja.com');
    });

    test('MULTI-7 Dashboard vendedor isolado', () {
      final pedroSales = AccessScopeService.filterSalesForScope(
        id: _sellerPedro(),
        sales: vendas,
        lojaId: 'loja-1',
      );
      final fat = pedroSales.fold<double>(0, (s, v) => s + v.total);
      final allFat = vendas.fold<double>(0, (s, v) => s + v.total);
      expect(fat, 200);
      expect(fat < allFat, isTrue);
    });

    test('MULTI-8 Financeiro oculto', () {
      expect(AccessScopeService.canAccessFinanceiro(_sellerPedro()), isFalse);
      expect(AccessScopeService.canAccessFinanceiro(_admin()), isTrue);
    });

    test('MULTI-9 Plano herdado da loja', () async {
      expect(AccessScopeService.sellerRequiresIndividualPlan(), isFalse);
      expect(AccessScopeService.shouldWritePlanFieldsOnSellerUserDoc(), isFalse);
      // Vendedor não passa pelo gate de plano próprio.
      // (PlanAccessResolver.enforcePlanGateForCurrentUser depende de Hive;
      //  aqui validamos a política estática e o contrato de escrita.)
      expect(UserRole.vendedor.needsPlanCheck, isFalse);
      expect(UserRole.admin.needsPlanCheck, isTrue);
    });

    test('MULTI-10 Nenhum vendedor precisa contratar plano', () {
      expect(AccessScopeService.sellerRequiresIndividualPlan(), isFalse);
      expect(AccessScopeService.canManageCampaigns(_sellerPedro()), isFalse);
      expect(AccessScopeService.canUseMarketingTools(_sellerPedro()), isTrue);
      expect(AccessScopeService.canEditStock(_sellerPedro()), isFalse);
      expect(AccessScopeService.canConsultStock(_sellerPedro()), isTrue);
    });

    test('MULTI-extra mapSaleBelongsToSeller com vendedorUid', () {
      expect(
        AccessScopeService.mapSaleBelongsToSeller(
          {'vendedorUid': 'pedro-uid', 'vendedor': 'Outro'},
          _sellerPedro(),
        ),
        isTrue,
      );
      expect(
        AccessScopeService.mapSaleBelongsToSeller(
          {'vendedorUid': 'maria-uid'},
          _sellerPedro(),
        ),
        isFalse,
      );
    });

    test('MULTI-extra carrinho por carteira', () {
      final wallet = AccessScopeService.buildSellerWalletKeys(
        id: _sellerPedro(),
        sales: vendas,
        lojaId: 'loja-1',
      );
      expect(
        AccessScopeService.canSeeCart(
          id: _sellerPedro(),
          walletCustomerKeys: wallet,
          customerName: 'João',
        ),
        isTrue,
      );
      expect(
        AccessScopeService.canSeeCart(
          id: _sellerPedro(),
          walletCustomerKeys: wallet,
          customerName: 'Ana',
        ),
        isFalse,
      );
      expect(
        AccessScopeService.canSeeCart(
          id: _sellerPedro(),
          walletCustomerKeys: wallet,
          createdByEmail: 'pedro@loja.com',
        ),
        isTrue,
      );
    });
  });
}
