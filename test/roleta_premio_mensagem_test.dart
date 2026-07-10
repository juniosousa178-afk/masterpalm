// M3.7-HOMOLOG-FINAL — ROLETAWA mensagem vendedor

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/premio_roleta_snapshot.dart';
import 'package:master_palm/services/pre_pedido_service.dart';

void main() {
  Map<String, dynamic> pedidoComPremio(Map<String, dynamic> premio) => {
        'id': 'pp1',
        'subtotal': 200,
        'total': 200,
        'pagamento': 'Mercado Pago',
        'frete': {'nome': 'PAC', 'valor': 15, 'gratis': false},
        'premioRoleta': premio,
      };

  group('ROLETAWA — mensagem WhatsApp novo pedido', () {
    test('ROLETAWA-1 percentual', () {
      final snap = premioRoletaFromFirestoreMap({
        'tipo': 'desconto',
        'codigo': 'P10',
        'valor': 10,
        'descricao': '10% OFF',
      });
      expect(
        PremioRoletaFormatter.linhaMensagemVendedor(snap!),
        'Cupom de 10% OFF',
      );
    });

    test('ROLETAWA-2 valor fixo', () {
      final snap = premioRoletaFromFirestoreMap({
        'tipo': 'valor_fixo',
        'codigo': 'V10',
        'valor': 10,
        'descricao': 'R\$ 10,00 OFF',
      });
      expect(
        PremioRoletaFormatter.linhaMensagemVendedor(snap!),
        'Cupom de R\$ 10,00 OFF',
      );
    });

    test('ROLETAWA-3 frete grátis', () {
      final snap = premioRoletaFromFirestoreMap({
        'tipo': 'frete_gratis',
        'codigo': 'FRETE_GRATIS',
        'valor': 0,
      });
      expect(
        PremioRoletaFormatter.linhaMensagemVendedor(snap!),
        'Frete grátis',
      );
    });

    test('ROLETAWA-4 payload legado sem valor numérico', () {
      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: pedidoComPremio({
          'tipo': 'desconto',
          'codigo': 'LEG99',
          'valor': 0,
          'descricao': '25% OFF',
        }),
        lojaId: 'loja',
      );
      expect(msg, isNot(contains('Cupom de 0% OFF')));
      expect(msg, contains('25% OFF'));
    });

    test('ROLETAWA-5 sem prêmio', () {
      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: {
          'id': 'x',
          'subtotal': 1,
          'total': 1,
          'pagamento': 'pix',
          'frete': {'nome': 'x', 'valor': 0},
        },
        lojaId: 'loja',
      );
      expect(msg, isNot(contains('PRÊMIO DA ROLETA')));
    });

    test('ROLETAWA-6 mensagem e formatter mesma descrição', () {
      final premio = {
        'tipo': 'desconto',
        'codigo': 'SYNC',
        'valor': 12,
        'descricao': '12% OFF',
      };
      final snap = premioRoletaFromFirestoreMap(premio)!;
      final linha = PremioRoletaFormatter.linhaMensagemVendedor(snap);
      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: pedidoComPremio(premio),
        lojaId: 'loja',
      );
      expect(msg, contains(linha));
    });
  });
}
