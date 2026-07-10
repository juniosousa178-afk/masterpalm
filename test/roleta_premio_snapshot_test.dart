// M3.7-HOMOLOG-FINAL — H12 contrato canônico prêmio roleta

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/premio_roleta_snapshot.dart';
import 'package:master_palm/services/pre_pedido_service.dart';

void main() {
  group('ROLETA snapshot — não exibir 0% OFF', () {
    test('RED legado: tipo desconto + valor 0 → não gera Cupom de 0% OFF', () {
      final snap = PremioRoletaSnapshot.fromFirestoreMap({
        'tipo': 'desconto',
        'codigo': 'ABC123',
        'valor': 0,
        'descricao': '10% OFF',
      });
      final linha = PremioRoletaFormatter.linhaMensagemVendedor(snap);
      expect(linha, isNot(contains('Cupom de 0% OFF')));
      expect(linha, contains('10% OFF'));
    });

    test('percentual explícito com valor', () {
      final snap = PremioRoletaSnapshot.fromCheckoutInputs(
        codigo: 'CUP10',
        descricao: '10% OFF',
        valorLegado: 10,
      );
      expect(snap, isNotNull);
      expect(snap!.tipo, PremioRoletaTipoCanonico.percentual);
      expect(
        PremioRoletaFormatter.linhaMensagemVendedor(snap),
        'Cupom de 10% OFF',
      );
    });

    test('valor fixo', () {
      final snap = PremioRoletaSnapshot.fromCheckoutInputs(
        codigo: 'R10',
        descricao: 'R\$ 10,00 OFF',
        valorLegado: 10,
      );
      expect(snap!.tipo, PremioRoletaTipoCanonico.valorFixo);
      expect(
        PremioRoletaFormatter.linhaMensagemVendedor(snap),
        'Cupom de R\$ 10,00 OFF',
      );
    });

    test('frete grátis — nunca percentual', () {
      final snap = PremioRoletaSnapshot.fromCheckoutInputs(
        codigo: 'FRETE_GRATIS',
        descricao: 'Frete Grátis',
        valorLegado: 100,
      );
      expect(snap!.tipo, PremioRoletaTipoCanonico.freteGratis);
      expect(
        PremioRoletaFormatter.linhaMensagemVendedor(snap),
        'Frete grátis',
      );
    });

    test('payload legado frete_gratis', () {
      final snap = premioRoletaFromFirestoreMap({
        'tipo': 'frete_gratis',
        'codigo': 'FRETE_GRATIS',
        'valor': 0,
        'descricao': 'Frete grátis',
      });
      expect(snap, isNotNull);
      expect(
        PremioRoletaFormatter.linhaMensagemVendedor(snap!),
        'Frete grátis',
      );
    });

    test('toFirestoreMap preserva protocolVersion', () {
      final snap = PremioRoletaSnapshot.fromCheckoutInputs(
        codigo: 'X1',
        descricao: '15% OFF',
        valorLegado: 15,
      );
      final map = snap!.toFirestoreMap(incluirTimestamp: false);
      expect(map['protocolVersion'], 1);
      expect(map['tipo'], 'desconto');
      expect(map['valor'], 15);
    });
  });

  group('ROLETA mensagem WhatsApp vendedor', () {
    test('mensagem usa helper canônico (não 0%)', () {
      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: {
          'id': 'ped1',
          'subtotal': 100,
          'total': 100,
          'pagamento': 'pix',
          'frete': {'nome': 'PAC', 'valor': 0, 'gratis': true},
          'premioRoleta': {
            'tipo': 'desconto',
            'codigo': 'ABC',
            'valor': 0,
            'descricao': '10% OFF',
          },
        },
        lojaId: 'loja1',
      );
      expect(msg, contains('PRÊMIO DA ROLETA'));
      expect(msg, isNot(contains('Cupom de 0% OFF')));
      expect(msg, contains('10% OFF'));
    });
  });
}
