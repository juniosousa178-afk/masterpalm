// lib/models/nota_fiscal.dart
import 'package:hive/hive.dart';

part 'nota_fiscal.g.dart';

@HiveType(typeId: 10) // Usando typeId 10 (ajuste se necessário)
class NotaFiscal extends HiveObject {
  /// Número da nota fiscal
  @HiveField(0)
  String numero;

  /// Série da nota fiscal
  @HiveField(1)
  String serie;

  /// Chave de acesso da NF-e (44 dígitos)
  @HiveField(2)
  String? chaveAcesso;

  /// Status da nota (emitida, cancelada, rejeitada, etc)
  @HiveField(3)
  String status;

  /// ID da venda vinculada
  @HiveField(4)
  String? vendaId;

  /// Dados do cliente
  @HiveField(5)
  String clienteNome;

  @HiveField(6)
  String clienteCpfCnpj;

  @HiveField(7)
  String? clienteEndereco;

  @HiveField(8)
  String? clienteCidade;

  @HiveField(9)
  String? clienteEstado;

  @HiveField(10)
  String? clienteCep;

  /// Dados da nota
  @HiveField(11)
  DateTime dataEmissao;

  @HiveField(12)
  double valorTotal;

  @HiveField(13)
  double valorProdutos;

  @HiveField(14)
  double valorFrete;

  @HiveField(15)
  double valorDesconto;

  /// Itens da nota
  @HiveField(16)
  List<NotaFiscalItem> itens;

  /// Informações fiscais
  @HiveField(17)
  double baseCalculoIcms;

  @HiveField(18)
  double valorIcms;

  @HiveField(19)
  String? protocoloAutorizacao;

  @HiveField(20)
  DateTime? dataAutorizacao;

  /// URL do XML da nota
  @HiveField(21)
  String? xmlUrl;

  /// URL do PDF/DANFE
  @HiveField(22)
  String? pdfUrl;

  /// ID da loja emitente
  @HiveField(23)
  String lojaId;

  /// ID no Firestore
  @HiveField(24)
  String? idFirebase;

  /// Observações
  @HiveField(25)
  String? observacoes;

  NotaFiscal({
    required this.numero,
    required this.serie,
    this.chaveAcesso,
    required this.status,
    this.vendaId,
    required this.clienteNome,
    required this.clienteCpfCnpj,
    this.clienteEndereco,
    this.clienteCidade,
    this.clienteEstado,
    this.clienteCep,
    required this.dataEmissao,
    required this.valorTotal,
    required this.valorProdutos,
    this.valorFrete = 0.0,
    this.valorDesconto = 0.0,
    required this.itens,
    this.baseCalculoIcms = 0.0,
    this.valorIcms = 0.0,
    this.protocoloAutorizacao,
    this.dataAutorizacao,
    this.xmlUrl,
    this.pdfUrl,
    required this.lojaId,
    this.idFirebase,
    this.observacoes,
  });

  /// Cria nota fiscal a partir de uma venda
  factory NotaFiscal.fromVenda({
    required String numero,
    required String serie,
    required String clienteNome,
    required String clienteCpfCnpj,
    String? clienteEndereco,
    String? clienteCidade,
    String? clienteEstado,
    String? clienteCep,
    required double valorTotal,
    required double valorProdutos,
    double valorFrete = 0.0,
    double valorDesconto = 0.0,
    required List<NotaFiscalItem> itens,
    required String lojaId,
    String? vendaId,
    String? observacoes,
  }) {
    return NotaFiscal(
      numero: numero,
      serie: serie,
      status: 'pendente',
      vendaId: vendaId,
      clienteNome: clienteNome,
      clienteCpfCnpj: clienteCpfCnpj,
      clienteEndereco: clienteEndereco,
      clienteCidade: clienteCidade,
      clienteEstado: clienteEstado,
      clienteCep: clienteCep,
      dataEmissao: DateTime.now(),
      valorTotal: valorTotal,
      valorProdutos: valorProdutos,
      valorFrete: valorFrete,
      valorDesconto: valorDesconto,
      itens: itens,
      lojaId: lojaId,
      observacoes: observacoes,
    );
  }

  /// Converte para Map (para Firestore)
  Map<String, dynamic> toMap() {
    return {
      'numero': numero,
      'serie': serie,
      'chaveAcesso': chaveAcesso,
      'status': status,
      'vendaId': vendaId,
      'clienteNome': clienteNome,
      'clienteCpfCnpj': clienteCpfCnpj,
      'clienteEndereco': clienteEndereco,
      'clienteCidade': clienteCidade,
      'clienteEstado': clienteEstado,
      'clienteCep': clienteCep,
      'dataEmissao': dataEmissao.toIso8601String(),
      'valorTotal': valorTotal,
      'valorProdutos': valorProdutos,
      'valorFrete': valorFrete,
      'valorDesconto': valorDesconto,
      'itens': itens.map((i) => i.toMap()).toList(),
      'baseCalculoIcms': baseCalculoIcms,
      'valorIcms': valorIcms,
      'protocoloAutorizacao': protocoloAutorizacao,
      'dataAutorizacao': dataAutorizacao?.toIso8601String(),
      'xmlUrl': xmlUrl,
      'pdfUrl': pdfUrl,
      'lojaId': lojaId,
      'observacoes': observacoes,
    };
  }
}

@HiveType(typeId: 11)
class NotaFiscalItem extends HiveObject {
  @HiveField(0)
  String produtoNome;

  @HiveField(1)
  String? codigoProduto;

  @HiveField(2)
  int quantidade;

  @HiveField(3)
  double valorUnitario;

  @HiveField(4)
  double valorTotal;

  @HiveField(5)
  String unidade; // UN, KG, M, etc

  @HiveField(6)
  String? ncm; // Código NCM

  @HiveField(7)
  String? cfop; // Código CFOP

  @HiveField(8)
  double? aliquotaIcms;

  NotaFiscalItem({
    required this.produtoNome,
    this.codigoProduto,
    required this.quantidade,
    required this.valorUnitario,
    required this.valorTotal,
    this.unidade = 'UN',
    this.ncm,
    this.cfop,
    this.aliquotaIcms,
  });

  Map<String, dynamic> toMap() {
    return {
      'produtoNome': produtoNome,
      'codigoProduto': codigoProduto,
      'quantidade': quantidade,
      'valorUnitario': valorUnitario,
      'valorTotal': valorTotal,
      'unidade': unidade,
      'ncm': ncm,
      'cfop': cfop,
      'aliquotaIcms': aliquotaIcms,
    };
  }
}
