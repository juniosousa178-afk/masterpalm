// M3.8 SPRINT3-MULTIUSUARIO-R2 — testes MULTI-11…20

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/utils/role_utils.dart';

Venda _v({
  required String cliente,
  String vendedor = '',
  String loja = 'loja-1',
  double total = 100,
  String? clienteId,
  String? vendedorUid,
  String? vendedorNome,
  String? vendedorEmail,
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
    vendedorUid: vendedorUid,
    vendedorNome: vendedorNome,
    vendedorEmail: vendedorEmail,
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
  group('MULTI-R2', () {
    final shared = [
      _v(
        cliente: 'João',
        clienteId: 'c-joao',
        vendedorUid: 'pedro-uid',
        vendedorNome: 'Pedro',
        vendedorEmail: 'pedro@loja.com',
        vendedor: 'Pedro',
      ),
      _v(
        cliente: 'João',
        clienteId: 'c-joao',
        vendedorUid: 'maria-uid',
        vendedorNome: 'Maria',
        vendedorEmail: 'maria@loja.com',
        vendedor: 'Maria',
      ),
    ];

    test('MULTI-11 Cliente compartilhado aparece para dois vendedores', () {
      final walletPedro = AccessScopeService.buildSellerWalletKeys(
        id: _sellerPedro(),
        sales: shared,
        lojaId: 'loja-1',
      );
      final walletMaria = AccessScopeService.buildSellerWalletKeys(
        id: _sellerMaria(),
        sales: shared,
        lojaId: 'loja-1',
      );
      expect(
        AccessScopeService.canSeeCustomer(
          id: _sellerPedro(),
          customerKey: 'c-joao',
          walletCustomerKeys: walletPedro,
        ),
        isTrue,
      );
      expect(
        AccessScopeService.canSeeCustomer(
          id: _sellerMaria(),
          customerKey: 'c-joao',
          walletCustomerKeys: walletMaria,
        ),
        isTrue,
      );
      expect(
        AccessScopeService.canSeeCustomer(
          id: _admin(),
          customerKey: 'c-joao',
          walletCustomerKeys: const {},
        ),
        isTrue,
      );
    });

    test('MULTI-12 Histórico mostra apenas vendas próprias', () {
      final hist = AccessScopeService.filterCustomerHistory(
        id: _sellerPedro(),
        sales: shared,
        lojaId: 'loja-1',
        customerName: 'João',
        customerId: 'c-joao',
      );
      expect(hist.length, 1);
      expect(hist.first.vendedorUid, 'pedro-uid');
    });

    test('MULTI-13 Dashboard vendedor não mostra faturamento geral', () {
      final all = [
        ...shared,
        _v(
          cliente: 'Ana',
          vendedorUid: 'maria-uid',
          total: 500,
          vendedor: 'Maria',
        ),
      ];
      final mine = AccessScopeService.filterSalesForScope(
        id: _sellerPedro(),
        sales: all,
        lojaId: 'loja-1',
      );
      final fatMine = mine.fold<double>(0, (s, v) => s + v.total);
      final fatAll = all.fold<double>(0, (s, v) => s + v.total);
      expect(fatMine, 100);
      expect(fatMine < fatAll, isTrue);
      expect(AccessScopeService.canSeeFinancial(_sellerPedro()), isFalse);
    });

    test('MULTI-14 Exportação respeita vendedor', () {
      final export = AccessScopeService.filterSalesForScope(
        id: _sellerPedro(),
        sales: shared,
        lojaId: 'loja-1',
      );
      expect(export.every((v) => AccessScopeService.canExport(_sellerPedro())),
          isTrue);
      expect(export.every((v) => v.vendedorUid == 'pedro-uid'), isTrue);
      expect(export.length, 1);
    });

    test('MULTI-15 Carrinho sem responsável só aparece para admin', () {
      final wallet = AccessScopeService.buildSellerWalletKeys(
        id: _sellerPedro(),
        sales: shared,
        lojaId: 'loja-1',
      );
      expect(
        AccessScopeService.canSeeCart(
          id: _admin(),
          walletCustomerKeys: wallet,
        ),
        isTrue,
      );
      expect(
        AccessScopeService.canSeeCart(
          id: _sellerPedro(),
          walletCustomerKeys: wallet,
        ),
        isFalse,
      );
      expect(
        AccessScopeService.canSeeCart(
          id: _sellerPedro(),
          walletCustomerKeys: wallet,
          assignedSellerUid: 'pedro-uid',
        ),
        isTrue,
      );
    });

    test('MULTI-16 Plano herdado exclusivamente da loja', () {
      expect(AccessScopeService.planBelongsToStoreOnly(), isTrue);
      expect(AccessScopeService.sellerRequiresIndividualPlan(), isFalse);
      expect(AccessScopeService.shouldWritePlanFieldsOnSellerUserDoc(), isFalse);
      expect(UserRole.vendedor.needsPlanCheck, isFalse);
    });

    test('MULTI-17 Nova venda grava vendedorUid', () {
      final nova = _v(
        cliente: 'João',
        vendedorUid: 'pedro-uid',
        vendedorNome: 'Pedro',
        vendedorEmail: 'pedro@loja.com',
        vendedor: 'pedro@loja.com',
      );
      expect(nova.vendedorUid, isNotEmpty);
      expect(
        AccessScopeService.sellerOwnsSale(nova, _sellerPedro()),
        isTrue,
      );
      expect(
        AccessScopeService.sellerOwnsSale(nova, _sellerMaria()),
        isFalse,
      );
    });

    test('MULTI-18 Fallback vendedorEmail funciona', () {
      final legacy = _v(
        cliente: 'João',
        vendedorEmail: 'pedro@loja.com',
        vendedor: 'outro',
      );
      expect(legacy.vendedorUid, isNull);
      expect(
        AccessScopeService.sellerOwnsSale(legacy, _sellerPedro()),
        isTrue,
      );
      expect(
        AccessScopeService.sellerOwnsSale(legacy, _sellerMaria()),
        isFalse,
      );
    });

    test('MULTI-19 Fallback vendedorNome funciona', () {
      final legacy = _v(
        cliente: 'João',
        vendedorNome: 'Pedro',
        vendedor: 'x',
      );
      expect(legacy.vendedorUid, isNull);
      expect(legacy.vendedorEmail, isNull);
      expect(
        AccessScopeService.sellerOwnsSale(legacy, _sellerPedro()),
        isTrue,
      );
    });

    test('MULTI-20 Registros novos usam somente vendedorUid', () {
      // uid presente e e-mail/nome de outro — match oficial só por uid.
      final nova = _v(
        cliente: 'João',
        vendedorUid: 'pedro-uid',
        vendedorNome: 'Maria',
        vendedorEmail: 'maria@loja.com',
        vendedor: 'maria@loja.com',
      );
      expect(
        AccessScopeService.sellerOwnsSale(nova, _sellerPedro()),
        isTrue,
      );
      expect(
        AccessScopeService.sellerOwnsSale(nova, _sellerMaria()),
        isFalse,
      );
      expect(
        AccessScopeService.currentSellerUid(_sellerPedro()),
        'pedro-uid',
      );
    });
  });
}
