// lib/models/venda.dart
import 'package:hive/hive.dart';
import 'venda_item.dart';

part 'venda.g.dart';

@HiveType(typeId: 1)
class Venda extends HiveObject {
  @HiveField(0)
  double preco;

  @HiveField(1)
  String produtosDescricao;

  @HiveField(2)
  int quantidade;

  @HiveField(3)
  String clienteNome;

  @HiveField(4)
  double total;

  @HiveField(5)
  String formasPagamento;

  @HiveField(6)
  DateTime data;

  @HiveField(7)
  String tamanho;

  @HiveField(8)
  double desconto; // %

  @HiveField(9)
  double frete;

  @HiveField(10)
  String vendedor;

  @HiveField(11)
  String observacao;

  @HiveField(12)
  List<VendaItem>? itens;

  // novos numéricos p/ relatório financeiro
  @HiveField(13, defaultValue: 0.0)
  double pagamentoDinheiro;

  @HiveField(14, defaultValue: 0.0)
  double pagamentoPix;

  @HiveField(15, defaultValue: 0.0)
  double pagamentoCartao;

  @HiveField(16, defaultValue: 0.0)
  double taxas; // R$ 3,50/un + 15% do custo

  @HiveField(17, defaultValue: 0.0)
  double custoProdutos; // soma do custo dos itens

  @HiveField(18, defaultValue: 0.0)
  double descontoValor;

  /// 🔹 Multi-loja: identifica a loja dona dessa venda
  /// (deixado opcional pra não quebrar vendas antigas do Hive)
  @HiveField(19)
  String? lojaId;

  /// 🔹 ID do documento no Firestore (para sincronização)
  /// (deixado opcional pra não quebrar vendas antigas do Hive)
  @HiveField(20)
  String? idFirebase;

  /// 🔹 ID estável do cliente (cliente.key ou idFirebase) para histórico
  /// Compatibilidade: vendas antigas sem este campo usam comparação por nome
  @HiveField(21)
  String? clienteId;

  /// Status legível para relatórios (opcional; legado sem campo = válido).
  @HiveField(22)
  String? statusVenda;

  @HiveField(23, defaultValue: false)
  bool cancelada;

  @HiveField(24, defaultValue: false)
  bool estornada;

  /// Ex.: catalogo_web, balcao, mp_webhook
  @HiveField(25)
  String? origemVenda;

  /// ID do pagamento Mercado Pago (reconciliação com estoque_vendas mp_*)
  @HiveField(26)
  String? paymentId;

  /// external_reference / mesmo id usado no checkout
  @HiveField(27)
  String? orderId;

  /// Documento em pre_pedidos ou pedidos_pendentes
  @HiveField(28)
  String? prePedidoId;

  /// Documento em `pedidos` finalizado (se houver)
  @HiveField(29)
  String? pedidoId;

  /// Rastreio do CMV agregado: [VendaOrigemCusto] — opcional (vendas antigas).
  @HiveField(30)
  String? origemCusto;

  Venda({
    required this.clienteNome,
    required this.produtosDescricao,
    required this.quantidade,
    required this.preco,
    required this.total,
    required this.formasPagamento,
    required this.data,
    this.tamanho = '',
    this.desconto = 0.0,
    this.frete = 0.0,
    required this.vendedor,
    required this.observacao,
    this.itens,
    this.pagamentoDinheiro = 0.0,
    this.pagamentoPix = 0.0,
    this.pagamentoCartao = 0.0,
    this.taxas = 0.0,
    this.custoProdutos = 0.0,
    this.descontoValor = 0.0,
    this.lojaId, // <- multi-loja
    this.idFirebase, // <- ID do Firestore
    this.clienteId, // <- ID estável do cliente
    this.statusVenda,
    this.cancelada = false,
    this.estornada = false,
    this.origemVenda,
    this.paymentId,
    this.orderId,
    this.prePedidoId,
    this.pedidoId,
    this.origemCusto,
  });

  /// Itens da venda (nunca null, fallback para [] em vendas antigas)
  List<VendaItem> get itensOuVazio => itens ?? [];

  double get recebidoInformado =>
      pagamentoDinheiro + pagamentoPix + pagamentoCartao;

  double get recebidoTotal => recebidoInformado > 0 ? recebidoInformado : total;

  /// Lucro operacional **igual ao relatório/fechamento**: use
  /// `FinanceiroRelatorioTaxas.lucroOperacionalVenda(this, cfg)` ou a extensão
  /// `v.lucroOperacional(cfg)` em `financeiro_relatorio_taxas.dart` com a config da loja.
  /// Não há getter sem config — evita divergência com `taxas == 0` (estimativa da loja).

  /// Descrição discriminada por forma: Dinheiro R$ X, Pix R$ Y, Cartão R$ Z
  String get formasPagamentoDiscriminado {
    final partes = <String>[];
    if (pagamentoDinheiro > 0) partes.add('Dinheiro: R\$ ${pagamentoDinheiro.toStringAsFixed(2).replaceAll('.', ',')}');
    if (pagamentoPix > 0) partes.add('Pix: R\$ ${pagamentoPix.toStringAsFixed(2).replaceAll('.', ',')}');
    if (pagamentoCartao > 0) partes.add('Cartão: R\$ ${pagamentoCartao.toStringAsFixed(2).replaceAll('.', ',')}');
    if (partes.isNotEmpty) return partes.join('\n');
    return formasPagamento.isNotEmpty ? formasPagamento : '—';
  }

  factory Venda.fromForm({
    required String clienteNome,
    required List<Map<String, dynamic>> produtos,
    required double desconto,
    required double frete,
    required Map<String, double> formasPagamento,
    required String vendedor,
    String observacao = '',
    double taxas = 0.0,
    double custoProdutos = 0.0,
    String? lojaId, // 🔹 multi-loja
  }) {
    // monta itens
    final parsedItens = produtos.map((item) {
      final nome = (item['produto'] ?? '').toString();
      final qtd = int.tryParse(item['quantidade'].toString()) ?? 1;
      final precoUnit = double.tryParse(item['preco'].toString()) ?? 0.0;
      final tam = (item['tamanho'] ?? '').toString();
      final cor = (item['cor'] ?? '').toString();
      final pid = (item['productId'] ?? '').toString().trim();
      final resumoExtra =
          (item['variacaoExtraResumo'] ?? '').toString().trim();
      final extraValor = (item['extraValor'] ?? '').toString().trim();
      final custoUnitario = (item['custoUnitario'] as num?)?.toDouble();

      return VendaItem(
        produtoNome: nome,
        quantidade: qtd,
        precoUnitario: precoUnit,
        tamanho: tam,
        cor: cor,
        productId: pid.isNotEmpty ? pid : null,
        variacaoExtraResumo: resumoExtra,
        extraValor: extraValor,
        custoUnitario: custoUnitario,
      );
    }).toList();

    // subtotal
    final subtotal = parsedItens.fold<double>(
      0.0,
      (acc, it) => acc + (it.precoUnitario * it.quantidade),
    );

    // total com desconto + frete
    final totalComDesconto = subtotal * (1 - desconto / 100) + frete;

    String fmt2(double v) => v.toStringAsFixed(2);

    final produtosDescricao = parsedItens.map((it) {
      final variacoes = <String>[];
      if (it.tamanho.isNotEmpty) variacoes.add('Tam: ${it.tamanho}');
      if (it.cor.isNotEmpty) variacoes.add('Cor: ${it.cor}');
      if (it.variacaoExtraResumo.isNotEmpty) {
        variacoes.add(it.variacaoExtraResumo);
      }
      final variacoesStr = variacoes.isNotEmpty ? ' (${variacoes.join(', ')})' : '';
      return "${it.quantidade} x ${it.produtoNome}$variacoesStr - R\$ ${fmt2(it.precoUnitario)}";
    }).join('\n');

    double vDinheiro = formasPagamento['dinheiro'] ?? 0.0;
    double vPix = formasPagamento['pix'] ?? 0.0;
    double vCartao =
        formasPagamento['cartao'] ?? (formasPagamento['cartão'] ?? 0.0);

    final formasTexto = [
      if (vDinheiro > 0) "Pagamento Dinheiro: R\$ ${fmt2(vDinheiro)}",
      if (vPix > 0) "Pagamento Pix: R\$ ${fmt2(vPix)}",
      if (vCartao > 0) "Pagamento Cartão: R\$ ${fmt2(vCartao)}",
    ].join('\n');

    final descricaoFinal = "$produtosDescricao\n"
        "Frete: R\$ ${fmt2(frete)}\n"
        "Desconto: ${desconto.toStringAsFixed(0)}%\n"
        "Total: R\$ ${fmt2(totalComDesconto)}\n"
        "$formasTexto";

    return Venda(
      clienteNome: clienteNome,
      produtosDescricao: descricaoFinal,
      quantidade: parsedItens.length,
      preco: subtotal,
      total: totalComDesconto,
      formasPagamento: formasTexto,
      data: DateTime.now(),
      desconto: desconto,
      frete: frete,
      vendedor: vendedor,
      observacao: observacao,
      itens: parsedItens,
      pagamentoDinheiro: vDinheiro,
      pagamentoPix: vPix,
      pagamentoCartao: vCartao,
      taxas: taxas,
      custoProdutos: custoProdutos,
      descontoValor: subtotal * (desconto / 100),
      lojaId: lojaId, // 🔹 salva a loja
      idFirebase: null, // 🔹 será preenchido após sync
    );
  }
}