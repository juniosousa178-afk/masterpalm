// M3.8 Sprint 1 — testes unitários dos módulos (R2)

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/carrinho_abandonado_ui.dart';
import 'package:master_palm/core/carrinho_recuperacao_score.dart';
import 'package:master_palm/core/communication_history_builder.dart';
import 'package:master_palm/core/pedido_cliente_snapshot_helpers.dart';
import 'package:master_palm/core/pedido_timeline_builder.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/customer_metrics_service.dart';
import 'package:master_palm/services/vendas_period_metrics_service.dart';

Venda _venda({
  required String cliente,
  required double total,
  double descontoValor = 0,
  double desconto = 0,
  double custoProdutos = 0,
  double taxas = 0,
  bool cancelada = false,
  DateTime? data,
}) {
  return Venda(
    clienteNome: cliente,
    produtosDescricao: 'X',
    quantidade: 1,
    preco: total,
    total: total,
    formasPagamento: 'pix',
    data: data ?? DateTime(2026, 7, 13, 10),
    vendedor: 't',
    observacao: '',
    itens: [
      VendaItem(produtoNome: 'X', quantidade: 1, precoUnitario: total),
    ],
    desconto: desconto,
    descontoValor: descontoValor,
    custoProdutos: custoProdutos,
    taxas: taxas,
    cancelada: cancelada,
    lojaId: 'loja-t',
  );
}

void main() {
  group('M3.8 S1 — Cliente snapshot helpers', () {
    test('endereço completo sem cortar campos', () {
      final c = {
        'nome': 'Ana',
        'cpf': '123',
        'telefone': '1199',
        'email': 'a@b.com',
        'endereco': {
          'rua': 'Rua das Flores',
          'numero': '100',
          'bairro': 'Centro',
          'cidade': 'São Paulo',
          'estado': 'SP',
          'cep': '01000-000',
          'complemento': 'Apto 2',
          'referencia': 'Próximo ao mercado',
        },
      };
      final t = formatarEnderecoSnapshotCompleto(c);
      expect(t, contains('Rua das Flores'));
      expect(t, contains('100'));
      expect(t, contains('Centro'));
      expect(t, contains('São Paulo'));
      expect(t, contains('SP'));
      expect(t, contains('01000-000'));
      expect(t, contains('Apto 2'));
      expect(t, contains('Próximo ao mercado'));
      expect(googleMapsUrlFromClienteSnapshot(c), contains('maps'));
      expect(whatsappUrlFromTelefone('11999990000'), contains('wa.me'));
    });
  });

  group('M3.8 S1 — Dashboard métricas', () {
    test('bruto = líquido + descontos; lucro simples; exclui canceladas', () {
      final now = DateTime(2026, 7, 13, 12);
      final vendas = [
        _venda(
          cliente: 'A',
          total: 100,
          descontoValor: 20,
          custoProdutos: 40,
          taxas: 5,
          data: now,
        ),
        _venda(cliente: 'B', total: 50, data: now, cancelada: true),
      ];
      final m = agregarVendasPeriodo(
        vendas,
        inicio: DateTime(2026, 7, 13),
        fimExclusivo: DateTime(2026, 7, 14),
        lojaId: 'loja-t',
      );
      expect(m.quantidade, 1);
      expect(m.liquido, 100);
      expect(m.descontos, 20);
      expect(m.bruto, 120);
      expect(m.lucro, 55); // 100 - 40 - 5
      expect(m.ticketMedio, 100);
    });
  });

  group('M3.8 S1 — Customer metrics', () {
    test('agrega pedidos e ticket; VIP/recorrente', () {
      final vendas = [
        _venda(cliente: 'Maria', total: 600, data: DateTime(2026, 1, 1)),
        _venda(cliente: 'Maria', total: 500, data: DateTime(2026, 6, 1)),
      ];
      final m = CustomerMetricsService.fromVendasList(
        vendas,
        clienteNome: 'Maria',
      );
      expect(m.quantidadePedidos, 2);
      expect(m.valorTotalComprado, 1100);
      expect(m.ticketMedio, 550);
      expect(m.recorrente, isTrue);
      expect(m.vip, isTrue);
    });
  });

  group('M3.8 S1 — Carrinhos status/score', () {
    test('normaliza status e score alta com regras H7', () {
      expect(normalizarStatusCarrinhoAbandonado('ativo'), kCarrinhoUiAbandonado);
      expect(
        labelStatusCarrinhoAbandonado('virou_venda'),
        'Virou Venda',
      );
      final s = calcularProbabilidadeRecuperacao(
        tempoAbandonado: const Duration(hours: 2),
        valorCarrinho: 350,
        quantidadeItens: 3,
        clienteRecorrente: true,
        temWhatsapp: true,
        temEmail: true,
      );
      expect(s.categoria, RecuperacaoProbabilidade.alta);
      expect(s.pontos, greaterThanOrEqualTo(60));
      expect(s.emojiBadge, '🟢');
    });

    test('score baixa sem contato e tempo longo', () {
      final s = calcularProbabilidadeRecuperacao(
        tempoAbandonado: const Duration(days: 10),
        valorCarrinho: 20,
        quantidadeItens: 1,
      );
      expect(s.categoria, RecuperacaoProbabilidade.baixa);
      expect(s.emojiBadge, '🔴');
    });

    test('total produtos', () {
      expect(
        totalCarrinhoProdutos([
          {'quantidade': 2, 'preco': 10.0},
          {'quantidade': 1, 'total': 5.0},
        ]),
        25,
      );
    });
  });

  group('M3.8 S1 — Timeline', () {
    test('marca só eventos reais; não inventa pagamento', () {
      final ev = buildPedidoTimeline({
        'id': 'p1',
        'createdAt': DateTime(2026, 7, 1),
        'statusPagamento': 'pendente',
      });
      expect(ev.any((e) => e.id == 'criado' && e.occurred), isTrue);
      expect(ev.any((e) => e.id == 'pay_ok' && e.occurred), isFalse);
      expect(ev.any((e) => e.id == 'pay_start' && e.occurred), isFalse);
      expect(ev.any((e) => e.id == 'whatsapp' && e.occurred), isFalse);
    });

    test('ocorridos filtra checklist fake', () {
      final ocorridos = buildPedidoTimelineOcorridos({
        'createdAt': DateTime(2026, 7, 1),
        'paidAt': DateTime(2026, 7, 1, 1),
        'statusPagamento': 'aprovado',
        'paymentId': 'mp-1',
        'numeroSorte': '12345',
        'mensagemEnviadaWhatsApp': true,
        'vendaId': 'v1',
        'estoqueBaixado': true,
      });
      expect(ocorridos.every((e) => e.occurred), isTrue);
      expect(ocorridos.any((e) => e.id == 'pay_ok'), isTrue);
      expect(ocorridos.any((e) => e.id == 'numero'), isTrue);
      expect(ocorridos.any((e) => e.id == 'whatsapp'), isTrue);
      expect(ocorridos.any((e) => e.id == 'email'), isFalse);
    });
  });

  group('M3.8 S1 — Comunicação', () {
    test('extrai canais reais com origem; sem fictício', () {
      final items = buildCommunicationHistory({
        'mensagemEnviadaWhatsApp': true,
        'emailEnviado': false,
        'statusPagamento': 'approved',
        'paymentId': 'mp-1',
        'premioRoleta': {'tipo': 'frete_gratis'},
        'numeroSorte': '99',
        'origem': 'catalogo',
      });
      expect(items.any((e) => e.channel == CommunicationChannel.whatsapp), isTrue);
      expect(items.any((e) => e.channel == CommunicationChannel.email), isTrue);
      expect(
        items.any((e) => e.channel == CommunicationChannel.mercadoPago),
        isTrue,
      );
      expect(items.any((e) => e.channel == CommunicationChannel.roleta), isTrue);
      expect(
        items.any((e) => e.channel == CommunicationChannel.numeroSorte),
        isTrue,
      );
      expect(
        buildCommunicationHistory({'foo': 1}).isEmpty,
        isTrue,
      );
    });
  });
}
