import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/migracao_vendas_itens_service.dart';

void main() {
  group('MigracaoVendasItensService.resolverItens', () {
    test('usa itens estruturados quando existem', () {
      final venda = Venda(
        clienteNome: 'Ana',
        produtosDescricao: 'ignorado',
        quantidade: 1,
        preco: 20,
        total: 20,
        formasPagamento: 'Pix',
        data: DateTime(2026, 1, 1),
        vendedor: 'Loja',
        observacao: '',
        itens: [
          VendaItem(
            produtoNome: 'Anel',
            quantidade: 2,
            precoUnitario: 10,
            tamanho: 'M',
            cor: 'Prata',
          ),
        ],
      );

      final itens = MigracaoVendasItensService.resolverItens(venda);
      expect(itens, hasLength(1));
      expect(itens.first.produtoNome, 'Anel');
      expect(itens.first.tamanho, 'M');
      expect(itens.first.cor, 'Prata');
    });

    test('reconstrói itens a partir de produtosDescricao', () {
      final venda = Venda(
        clienteNome: 'Ana',
        produtosDescricao:
            '2 x Colar Lua (Tam: U, Cor: Dourado, Letra: A) - R\$ 45.00\n'
            '1 x Brinco Sol (Tam: P) - R\$ 20.50\n'
            'Frete: R\$ 0.00\n'
            'Desconto: 0%\n'
            'Total: R\$ 110.50\n'
            'Pagamento Pix: R\$ 110.50',
        quantidade: 2,
        preco: 110.5,
        total: 110.5,
        formasPagamento: 'Pix',
        data: DateTime(2026, 1, 1),
        vendedor: 'Loja',
        observacao: '',
        itens: null,
      );

      final itens = MigracaoVendasItensService.resolverItens(venda);
      expect(itens, hasLength(2));
      expect(itens[0].produtoNome, 'Colar Lua');
      expect(itens[0].quantidade, 2);
      expect(itens[0].precoUnitario, 45.0);
      expect(itens[0].tamanho, 'U');
      expect(itens[0].cor, 'Dourado');
      expect(itens[0].variacaoExtraResumo, 'Letra: A');
      expect(itens[1].produtoNome, 'Brinco Sol');
      expect(itens[1].tamanho, 'P');
      expect(itens[1].precoUnitario, 20.5);
    });
  });
}
