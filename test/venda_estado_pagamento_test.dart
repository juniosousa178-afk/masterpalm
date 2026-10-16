// Edição de venda: o editor abre com o estado de pagamento salvo e só muda com decisão explícita.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/venda_estado_pagamento.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/screens/nova_venda/finalizar_confirmacao_dialog.dart';
import 'package:master_palm/widgets/moeda_text_field.dart';

Venda _venda({
  double total = 300,
  double dinheiro = 0,
  double pix = 0,
  double cartao = 0,
  String formas = '',
}) =>
    Venda(
      clienteNome: 'Cliente',
      produtosDescricao: 'desc',
      quantidade: 1,
      preco: total,
      total: total,
      formasPagamento: formas,
      data: DateTime(2026, 9, 9),
      vendedor: 'App',
      observacao: '',
      pagamentoDinheiro: dinheiro,
      pagamentoPix: pix,
      pagamentoCartao: cartao,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hoje = DateTime(2026, 10, 15);

  group('hidratarPagamentoEdicao — matriz', () {
    test('A 100% fiado: abre fiado, Pix vazio, vencimento e saldo salvos', () {
      final h = hidratarPagamentoEdicao(
        _venda(formas: 'Fiado - R\$ 300,00. Vencimento: 10/11/2026'),
        hoje: hoje,
      );
      expect(h.fiado, isTrue);
      expect(h.pagamentos, [
        {'forma': 'Pix', 'valor': 0.0},
      ]);
      expect(h.vencimentoFiado, DateTime(2026, 11, 10));
      expect(h.diasVencimento, 26);
      expect(h.quantidadeParcelas, 1);
    });

    test('B Pix + fiado: mantém só o Pix pago', () {
      final h = hidratarPagamentoEdicao(
        _venda(
          pix: 100,
          formas: 'Pagamento Pix: R\$ 100,00\nFiado - R\$ 200,00. Vencimento: 10/11/2026',
        ),
        hoje: hoje,
      );
      expect(h.fiado, isTrue);
      expect(h.pagamentos, [
        {'forma': 'Pix', 'valor': 100.0},
      ]);
    });

    test('C fiado parcelado (com recebimentos na conta): parcelas e intervalo preservados', () {
      final h = hidratarPagamentoEdicao(
        _venda(
          formas: 'Fiado - R\$ 300,00. Vencimento: 10/11/2026 '
              'Parcelas fiado: 3. Intervalo: 15 dias.',
        ),
        hoje: hoje,
      );
      expect(h.fiado, isTrue);
      expect(h.quantidadeParcelas, 3);
      expect(h.intervaloDias, 15);
      expect(h.pagamentos.single['valor'], 0.0);
    });

    test('D 100% Pix: continua Pix', () {
      final h = hidratarPagamentoEdicao(
        _venda(pix: 300, formas: 'Pagamento Pix: R\$ 300,00'),
        hoje: hoje,
      );
      expect(h.fiado, isFalse);
      expect(h.pagamentos, [
        {'forma': 'Pix', 'valor': 300.0},
      ]);
    });

    test('E dinheiro + cartão: formas e valores salvos', () {
      final h = hidratarPagamentoEdicao(
        _venda(dinheiro: 100, cartao: 200),
        hoje: hoje,
      );
      expect(h.fiado, isFalse);
      expect(h.pagamentos, [
        {'forma': 'Dinheiro', 'valor': 100.0},
        {'forma': 'Cartão', 'valor': 200.0},
      ]);
    });

    test('F fiado com conta quitada/encerrada: a venda continua fiada no editor', () {
      final h = hidratarPagamentoEdicao(
        _venda(formas: 'Fiado - R\$ 300,00. Vencimento: 01/09/2026'),
        hoje: hoje,
      );
      expect(h.fiado, isTrue);
      expect(h.vencimentoFiado, DateTime(2026, 9, 1));
      expect(h.diasVencimento, 1, reason: 'vencido: campo de dias válido, data salva preservada');
    });

    test('texto "Fiado" antigo com tudo pago não é fiado', () {
      final h = hidratarPagamentoEdicao(
        _venda(pix: 300, formas: 'Pagamento Pix: R\$ 300,00\nFiado - R\$ 0,00.'),
        hoje: hoje,
      );
      expect(h.fiado, isFalse);
    });

    test('venda legada sem campos de pagamento e sem fiado mantém o comportamento anterior', () {
      final h = hidratarPagamentoEdicao(_venda(), hoje: hoje);
      expect(h.fiado, isFalse);
      expect(h.pagamentos, [
        {'forma': 'Pix', 'valor': 300.0},
      ]);
    });
  });

  group('EstadoPagamentoVenda', () {
    test('editor hidratado sem mudanças = estado salvo (A, B, D, E)', () {
      final casos = [
        (_venda(formas: 'Fiado - R\$ 300,00. Vencimento: 10/11/2026'), true, 0.0, 0.0, 0.0),
        (_venda(pix: 100, formas: 'Pagamento Pix\nFiado - R\$ 200,00. Vencimento: 10/11/2026'), true, 0.0, 100.0, 0.0),
        (_venda(pix: 300, formas: 'Pagamento Pix: R\$ 300,00'), false, 0.0, 300.0, 0.0),
        (_venda(dinheiro: 100, cartao: 200), false, 100.0, 0.0, 200.0),
      ];
      for (final (v, fiado, din, pix, cartao) in casos) {
        final antes = EstadoPagamentoVenda.daVenda(v);
        final depois = EstadoPagamentoVenda.daEdicao(
          isFiado: fiado,
          total: v.total,
          dinheiro: din,
          pix: pix,
          cartao: cartao,
        );
        expect(antes.equivalente(depois), isTrue, reason: '$antes × $depois');
      }
    });

    test('fiado → Pix total é mudança; produto removido mantendo fiado não é', () {
      final antes = EstadoPagamentoVenda.daVenda(
        _venda(total: 8179, formas: 'Fiado - R\$ 8179,00. Vencimento: 10/11/2026'),
      );
      expect(
        antes.equivalente(EstadoPagamentoVenda.daEdicao(isFiado: false, total: 312, pix: 312)),
        isFalse,
      );
      expect(
        antes.equivalente(EstadoPagamentoVenda.daEdicao(isFiado: true, total: 312)),
        isTrue,
      );
    });

    test('não fiado sem pagamento informado normaliza para Dinheiro (igual ao serviço)', () {
      final e = EstadoPagamentoVenda.daEdicao(isFiado: false, total: 50);
      expect(e.fiado, isFalse);
      expect(e.dinheiro, 50);
    });

    test('toJson em centavos, no formato do servidor', () {
      expect(
        const EstadoPagamentoVenda(fiado: true, pix: 40.004).toJson(),
        {'fiado': true, 'dinheiro': 0.0, 'pix': 40.0, 'cartao': 0.0},
      );
    });
  });

  group('mensagens', () {
    const msgServidor =
        'Esta venda possui uma conta a receber ativa. Para alterar a forma de pagamento, '
        'atualize o MasterPalm e confirme a mudança no campo de pagamento. Nenhuma alteração foi feita.';

    test('rejeição do servidor (cancelled) não vira erro de estoque', () {
      final e = FirebaseFunctionsException(
        code: 'cancelled',
        message: msgServidor,
        details: {'code': 'PAYMENT_CHANGE_REQUIRES_CONFIRMATION'},
      );
      final texto = formatSalvarVendaErrorForUser(e);
      expect(texto, contains('confirme a mudança'));
      expect(texto, contains('Nenhuma alteração foi feita'));
      expect(texto, isNot(contains('estoque')));
    });

    test('bloqueio local explica o que fazer', () {
      final texto = formatSalvarVendaErrorForUser(AlteracaoPagamentoNaoConfirmadaException());
      expect(texto, AlteracaoPagamentoNaoConfirmadaException.mensagem);
    });
  });

  group('FinalizarVendaConfirmacaoDialog — edição de venda fiada', () {
    Future<FinalizarVendaResult?> abrirEConfirmar(
      WidgetTester tester, {
      List<Map<String, dynamic>> pagamentos = const [
        {'forma': 'Pix', 'valor': 0.0},
      ],
      bool fiado = true,
      int parcelas = 1,
      Future<void> Function()? interagir,
    }) async {
      FinalizarVendaResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await FinalizarVendaConfirmacaoDialog.show(
                      ctx,
                      total: 300,
                      resumoProdutos: const [
                        {'produto': 'Produto', 'quantidade': 1, 'preco': 300.0},
                      ],
                      initialPagamentos: pagamentos,
                      initialFiado: fiado,
                      initialDiasVencimento: 26,
                      initialQuantidadeParcelasFiado: parcelas,
                      initialIntervaloParcelasDias: 15,
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      if (interagir != null) await interagir();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar venda').last);
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('100% fiado abre marcado, Pix vazio e saldo correto', (tester) async {
      final r = await abrirEConfirmar(tester, interagir: () async {
        final campo = tester.widget<MoedaTextField>(find.byType(MoedaTextField).first);
        expect(campo.controller.text, isEmpty, reason: 'Pix não é preenchido sozinho');
        expect(find.text('Saldo fiado: R\$ 300,00'), findsOneWidget);
        final check = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
        expect(check.value, isTrue);
      });
      expect(r, isNotNull);
      expect(r!.isFiado, isTrue);
      expect(r.pagamentos, isEmpty);
      expect(r.diasVencimento, 26);
      expect(r.pagamentoAlteradoPeloUsuario, isFalse);
      expect(r.termosFiadoAlterados, isFalse);
    });

    testWidgets('Pix + fiado mantém o Pix pago e o saldo', (tester) async {
      final r = await abrirEConfirmar(
        tester,
        pagamentos: const [
          {'forma': 'Pix', 'valor': 100.0},
        ],
        interagir: () async {
          expect(find.text('Saldo fiado: R\$ 200,00'), findsOneWidget);
        },
      );
      expect(r!.isFiado, isTrue);
      expect(r.pagamentos, [
        {'forma': 'Pix', 'valor': 100.0},
      ]);
      expect(r.pagamentoAlteradoPeloUsuario, isFalse);
    });

    testWidgets('parcelado abre com parcelas e intervalo salvos', (tester) async {
      final r = await abrirEConfirmar(tester, parcelas: 3);
      expect(r!.quantidadeParcelasFiado, 3);
      expect(r.intervaloParcelasDias, 15);
      expect(r.termosFiadoAlterados, isFalse);
    });

    testWidgets('desmarcar fiado é mudança explícita de pagamento', (tester) async {
      final r = await abrirEConfirmar(tester, interagir: () async {
        await tester.tap(find.text('Venda fiada (conta a receber)'));
        await tester.pumpAndSettle();
      });
      expect(r!.isFiado, isFalse);
      expect(r.pagamentos, [
        {'forma': 'Pix', 'valor': 300.0},
      ]);
      expect(r.pagamentoAlteradoPeloUsuario, isTrue);
    });

    testWidgets('mudar vencimento não é mudança de pagamento', (tester) async {
      final r = await abrirEConfirmar(tester, interagir: () async {
        await tester.enterText(find.widgetWithText(TextField, '1º vencimento em (dias)'), '40');
        await tester.pumpAndSettle();
      });
      expect(r!.isFiado, isTrue);
      expect(r.diasVencimento, 40);
      expect(r.termosFiadoAlterados, isTrue);
      expect(r.pagamentoAlteradoPeloUsuario, isFalse);
    });

    testWidgets('digitar valor de pagamento é mudança explícita', (tester) async {
      final r = await abrirEConfirmar(tester, interagir: () async {
        await tester.enterText(find.byType(MoedaTextField).first, '5000');
        await tester.pumpAndSettle();
      });
      expect(r!.isFiado, isTrue);
      expect(r.pagamentos.single['valor'], 50.0);
      expect(r.pagamentoAlteradoPeloUsuario, isTrue);
    });

    testWidgets('venda nova (não fiada) mantém a sugestão do total', (tester) async {
      final r = await abrirEConfirmar(tester, fiado: false);
      expect(r!.isFiado, isFalse);
      expect(r.pagamentos, [
        {'forma': 'Pix', 'valor': 300.0},
      ]);
      expect(r.pagamentoAlteradoPeloUsuario, isFalse);
    });
  });
}
