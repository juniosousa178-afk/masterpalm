import 'package:hive/hive.dart';
import '../core/logger.dart';
import '../models/produto.dart';
import '../models/venda_item.dart';

class FinanceRules {
  static const double embalagemUnit = 3.50;
  static const double percFixosSobreCusto = 0.15;

  static Future<({double custoProdutos, double taxas})> calcular({
    required List<VendaItem> itens,
    Box<Produto>• produtosBox,
  }) async {
    final Box<Produto> box;
    if (produtosBox != null) {
      box = produtosBox;
    } else {
      logW(
        '[LEGADO_BOX] FinanceRules.calcular usando box genérica "produtos" | fluxo legado, não multi-loja',
        tag: 'LEGADO_BOX',
      );
      box = Hive.box<Produto>('produtos');
    }
    double custoProdutos = 0.0;
    double taxas = 0.0;

    for (final it in itens) {
      final prod = box.values.firstWhere(
        (p) => p.nome.toLowerCase() == it.produtoNome.toLowerCase(),
        orElse: () => Produto(
          nome: it.produtoNome,
          custoReal: 0.0,
          frete: 0.0,
          gastosFixos: 0.0,
          gastosVariaveis: 0.0,
          precoSugerido: 0.0,
          precoFinal: it.precoUnitario,
          quantidade: 0,
          precoUnitario: it.precoUnitario,
          categoria: 'Desconhecida',
          dataEntrada: DateTime.now(),
        ),
      );

      final custoUnit = prod.custoReal;
      final q = it.quantidade;

      custoProdutos += custoUnit * q;
      taxas += (embalagemUnit * q) + (percFixosSobreCusto * custoUnit * q);
    }

    return (custoProdutos: custoProdutos, taxas: taxas);
  }
}
