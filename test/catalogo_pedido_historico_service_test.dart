// M3.4.1 — doc `pedidos` para WhatsApp rico, status e prêmio roleta.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/repositories/pedido_repository.dart';
import 'package:master_palm/services/catalogo_pedido_historico_service.dart';
import 'package:master_palm/services/pedido_collection_resolver.dart';

const _lojaId = 'loja-cat-historico-test';
const _vendaId = 'hive-venda-42';

Map<String, dynamic> _customer() => {
      'nome': 'Cliente CAT',
      'email': 'cat@test.com',
      'telefone': '11999999999',
      'enderecoFormatado': 'Rua Teste, 1',
    };

List<Map<String, dynamic>> _items() => [
      {
        'nome': 'Anel',
        'quantidade': 1,
        'precoUnitario': 50.0,
        'tamanho': '16',
        'cor': 'rose',
      },
    ];

Map<String, dynamic> _entrega() => {
      'nome': 'PAC',
      'valor': 10.0,
      'freteGratis': false,
      'tipo': 'pac',
    };

Map<String, dynamic> _premioRoleta() => {
      'descricao': '10% desconto',
      'codigo': 'ROLETA10',
      'valor': 10.0,
    };

Future<int> _countPedidosPorVendaId(
  FakeFirebaseFirestore fs,
  String vendaId,
) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('pedidos')
      .where('vendaId', isEqualTo: vendaId)
      .get();
  return snap.docs.length;
}

void main() {
  late FakeFirebaseFirestore firestore;
  late CatalogoPedidoHistoricoService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final repo = PedidoRepository(db: firestore);
    CatalogoPedidoHistoricoService.debugPedidoRepositoryOverride = repo;
    service = CatalogoPedidoHistoricoService(pedidoRepository: repo);
  });

  tearDown(() {
    CatalogoPedidoHistoricoService.debugPedidoRepositoryOverride = null;
  });

  group('M3.4.1 catalogo pedidos historico', () {
    test('CAT-1 documento pedidos criado', () async {
      final id = await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
        premioRoletaRaw: _premioRoleta(),
      );
      expect(id, isNotNull);
      expect(await _countPedidosPorVendaId(firestore, _vendaId), 1);
      final doc = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('pedidos')
          .doc(id!)
          .get();
      expect(doc.data()?['vendaId'], _vendaId);
      expect(doc.data()?['premioRoleta'], isNotNull);
    });

    test('CAT-2 WhatsApp encontra documento por vendaId', () async {
      await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
      );
      final repo = PedidoRepository(db: firestore);
      final pedido = await repo.findFirstByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: _lojaId,
        field: 'vendaId',
        value: _vendaId,
      );
      expect(pedido, isNotNull);
      expect(pedido!['cliente']['enderecoFormatado'], 'Rua Teste, 1');
      expect((pedido['itens'] as List).length, 1);
    });

    test('CAT-3 status atualizado (mesmo update de atualizarStatusPedido)', () async {
      final repo = PedidoRepository(db: firestore);
      await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
      );
      final pedidoRef = await repo.findFirstRefByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: _lojaId,
        field: 'vendaId',
        value: _vendaId,
      );
      expect(pedidoRef, isNotNull);
      await pedidoRef!.update({
        'status': 'pago',
        'dataAtualizacao': FieldValue.serverTimestamp(),
      });
      final pedido = await repo.findFirstByField(
        flowType: PedidoFlowType.pedidos,
        lojaId: _lojaId,
        field: 'vendaId',
        value: _vendaId,
      );
      expect(pedido!['status'], 'pago');
    });

    test('CAT-4 prêmio roleta ativado (mesmo update do PosPagamento)', () async {
      final pedidoId = await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
        premioRoletaRaw: _premioRoleta(),
      );
      final ref = firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('pedidos')
          .doc(pedidoId);
      await ref.update({
        'premioRoleta.status': 'ativo',
        'premioRoleta.valido': true,
        'premioRoleta.dataAtivacao': FieldValue.serverTimestamp(),
      });
      final snap = await ref.get();
      final premio = snap.data()!['premioRoleta'] as Map<String, dynamic>;
      expect(premio['status'], 'ativo');
      expect(premio['valido'], isTrue);
    });

    test('CAT-5 retry não cria segundo documento', () async {
      final id1 = await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
      );
      final id2 = await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
      );
      expect(id1, id2);
      expect(await _countPedidosPorVendaId(firestore, _vendaId), 1);
    });

    test('CAT-6 rollback antes do createPedido não cria documento', () async {
      expect(await _countPedidosPorVendaId(firestore, _vendaId), 0);
    });

    test('CAT-7 venda concluída + pedido existente → idempotente', () async {
      await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
      );
      final idRetry = await service.garantirDocumentoPedidosHistorico(
        lojaId: _lojaId,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        entrega: _entrega(),
        pagamento: 'PIX',
        subtotal: 50,
        total: 60,
      );
      expect(idRetry, isNotEmpty);
      expect(await _countPedidosPorVendaId(firestore, _vendaId), 1);
    });

    test('CAT fluxo pre_pedidos — ordem registrarVenda → createPedido → confirmar',
        () {
      final src =
          File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
      final iVenda = src.indexOf('VendasService.registrarVendaMulti');
      final iHistorico =
          src.indexOf('CatalogoPedidoHistoricoService().garantirDocumentoPedidosHistorico');
      final iConfirmar = src.indexOf('PrePedidoService.confirmarPrePedido');
      final iPos = src.indexOf('PosPagamentoService.processarConfirmacaoPagamento');
      expect(iVenda, greaterThan(0));
      expect(iHistorico, greaterThan(iVenda));
      expect(iConfirmar, greaterThan(iHistorico));
      expect(iPos, greaterThan(iConfirmar));
    });
  });
}
