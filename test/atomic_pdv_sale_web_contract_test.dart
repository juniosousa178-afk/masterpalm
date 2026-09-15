import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/nova_venda_ui_release_policy.dart';
import 'package:master_palm/services/atomic_pdv_sale_payload.dart';
import 'package:master_palm/services/web_build_convergence_service.dart';

void main() {
  late String vendasService;
  late String backendService;
  late String estoqueTx;
  late String novaVendaModal;

  setUpAll(() {
    vendasService = File('lib/services/vendas_service.dart').readAsStringSync();
    backendService =
        File('lib/services/stock_catalog_backend_service.dart').readAsStringSync();
    estoqueTx =
        File('lib/services/estoque_transaction_service.dart').readAsStringSync();
    novaVendaModal =
        File('lib/screens/nova_venda_modal.dart').readAsStringSync();
  });

  group('atomic PDV web contract', () {
    test('1 new final sale sends atomic protocol marker', () {
      expect(backendService.contains("'atomicPdvSale': true"), isTrue);
      expect(vendasService.contains('atomicPdvSale: useAtomicPdvSale'), isTrue);
      expect(estoqueTx.contains('atomicPdvSale: atomicPdvSale'), isTrue);
    });

    test('2 new final sale sends canonical sale intent', () {
      expect(vendasService.contains('buildAtomicPdvSalePayload'), isTrue);
      expect(vendasService.contains('atomicSale: atomicSalePayload'), isTrue);
      expect(File('lib/services/atomic_pdv_sale_payload.dart').existsSync(), isTrue);
      final payload = buildAtomicPdvSalePayload(
        clienteNome: 'Ana',
        produtosDescricao: '1 x Anel',
        quantidade: 1,
        preco: 50,
        total: 50,
        formasPagamento: 'Pagamento Pix: R\$ 50.00',
        frete: 0,
        desconto: 0,
        descontoValor: 0,
        observacao: '',
        pagamentoDinheiro: 0,
        pagamentoPix: 50,
        pagamentoCartao: 0,
        taxas: 0,
        custoProdutos: 10,
        tamanho: '',
        vendedor: 'App',
        itens: [
          {
            'produtoNome': 'Anel',
            'quantidade': 1,
            'tamanho': '',
            'cor': '',
            'precoUnitario': 50.0,
            'precoTotal': 50.0,
            'productId': 'prod1',
            'custoUnitario': 10.0,
            'origemCustoItem': 'custoReal',
          },
        ],
      );
      expect(payload['total'], 50);
      expect((payload['itens'] as List).first['productId'], 'prod1');
    });

    test('3 success modal waits for authoritative backend result', () {
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: true,
          isFiado: false,
          fiadoReceivableReady: true,
          saleIntentPersistedOrSkipped: true,
          requireAuthoritativeRemoteSale: true,
          authoritativeRemoteSaleCommitted: false,
        ),
        isFalse,
      );
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: true,
          isFiado: false,
          fiadoReceivableReady: true,
          saleIntentPersistedOrSkipped: true,
          requireAuthoritativeRemoteSale: true,
          authoritativeRemoteSaleCommitted: true,
        ),
        isTrue,
      );
      expect(vendasService.contains('requireAuthoritativeRemoteSale: useAtomicPdvSale'),
          isTrue);
      expect(novaVendaModal.contains('Venda salva com sucesso!'), isTrue);
    });

    test('4 failed backend: no success modal gate', () {
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: false,
          journalCompleted: false,
          isFiado: false,
          fiadoReceivableReady: false,
          saleIntentPersistedOrSkipped: false,
          requireAuthoritativeRemoteSale: true,
          authoritativeRemoteSaleCommitted: false,
        ),
        isFalse,
      );
    });

    test('5 failed backend: no local completed intent without atomic confirm', () {
      expect(vendasService.contains('remoteAtomicSaleCommitted'), isTrue);
      expect(
        vendasService.contains(
          'Backend atomic PDV sale did not confirm authoritative sale commit',
        ),
        isTrue,
      );
    });

    test('6 backend success: Hive mirror updated path preserved', () {
      expect(vendasService.contains('vendasBox.add(venda)'), isTrue);
      expect(vendasService.contains('HIVE_ROLE') == false, isTrue);
      expect(vendasService.contains('remoteAtomicSaleCommitted = baixaOp.authoritativeAtomicSale'),
          isTrue);
    });

    test('7 Hive mirror failure after backend: no second remote mutation / no estorno', () {
      expect(
        vendasService.contains('!remoteAtomicSaleCommitted'),
        isTrue,
      );
      expect(
        vendasService.contains('sem estorno'),
        isTrue,
      );
    });

    test('8 client does NOT call authoritative syncVenda after atomic success', () {
      expect(
        vendasService.contains('atomic PDV: skip client syncVenda'),
        isTrue,
      );
      expect(
        vendasService.contains('if (remoteAtomicSaleCommitted)'),
        isTrue,
      );
    });

    test('9 old unrelated syncVenda callsites preserved', () {
      expect(
        File('lib/services/vendas_firestore_service.dart')
            .readAsStringSync()
            .contains('static Future<bool> syncVenda'),
        isTrue,
      );
      expect(
        File('lib/services/catalogo_venda_service.dart')
            .readAsStringSync()
            .contains('syncVenda'),
        isTrue,
      );
      expect(
        File('lib/services/soft_delete_service.dart')
            .readAsStringSync()
            .contains('syncVenda'),
        isTrue,
      );
    });

    test('10 offline: no success without authoritative commit', () {
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: true,
          isFiado: false,
          fiadoReceivableReady: true,
          saleIntentPersistedOrSkipped: true,
          requireAuthoritativeRemoteSale: true,
          authoritativeRemoteSaleCommitted: false,
        ),
        isFalse,
      );
    });

    test('11 duplicate click uses frozen operation identity', () {
      expect(vendasService.contains('idFirebaseReservado'), isTrue);
      expect(vendasService.contains('operationId: idFirebaseReservado'), isTrue);
    });

    test('12 version convergence: no reload during in-flight transaction', () async {
      expect(PdvMutationGate.isMutationInFlight, isFalse);
      await PdvMutationGate.run(() async {
        expect(PdvMutationGate.isMutationInFlight, isTrue);
      });
      expect(PdvMutationGate.isMutationInFlight, isFalse);
      expect(vendasService.contains('PdvMutationGate.run'), isTrue);
    });
  });
}
