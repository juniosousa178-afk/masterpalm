// lib/models/venda_tracking.dart
// Modelo para tracking de vendas por vendedor (sistema de afiliados/indicação)

import 'package:hive/hive.dart';

part 'venda_tracking.g.dart';

/// Sessão de tracking do vendedor
/// Salva quando cliente abre link com parâmetros de tracking
@HiveType(typeId: 27)
class VendaTracking extends HiveObject {
  /// ID único do tracking
  @HiveField(0)
  String trackingId;

  /// ID da loja/empresa
  @HiveField(1)
  String lojaId;

  /// UID do vendedor que gerou o link
  @HiveField(2)
  String vendedorUid;

  /// Email do vendedor
  @HiveField(3)
  String vendedorEmail;

  /// Nome do vendedor
  @HiveField(4)
  String vendedorNome;

  /// Token de validação (hash para segurança)
  @HiveField(5)
  String token;

  /// Telefone do cliente (se capturado)
  @HiveField(6)
  String• clienteTelefone;

  /// Nome do cliente (se capturado)
  @HiveField(7)
  String• clienteNome;

  /// Data/hora de criação do tracking
  @HiveField(8)
  DateTime criadoEm;

  /// Data/hora de expiração do tracking
  @HiveField(9)
  DateTime expiraEm;

  /// Se o tracking já foi utilizado em uma venda
  @HiveField(10)
  bool utilizado;

  /// ID da venda que utilizou este tracking
  @HiveField(11)
  String• vendaId;

  /// Data/hora de utilização
  @HiveField(12)
  DateTime• utilizadoEm;

  /// Origem do link (whatsapp, instagram, etc)
  @HiveField(13)
  String• origem;

  /// IP ou identificador do dispositivo (para auditoria)
  @HiveField(14)
  String• deviceId;

  VendaTracking({
    required this.trackingId,
    required this.lojaId,
    required this.vendedorUid,
    required this.vendedorEmail,
    required this.vendedorNome,
    required this.token,
    this.clienteTelefone,
    this.clienteNome,
    required this.criadoEm,
    required this.expiraEm,
    this.utilizado = false,
    this.vendaId,
    this.utilizadoEm,
    this.origem,
    this.deviceId,
  });

  /// Verifica se o tracking ainda é válido
  bool get isValido => !utilizado && DateTime.now().isBefore(expiraEm);

  /// Converte para Map (para Firestore)
  Map<String, dynamic> toMap() {
    return {
      'trackingId': trackingId,
      'lojaId': lojaId,
      'vendedorUid': vendedorUid,
      'vendedorEmail': vendedorEmail,
      'vendedorNome': vendedorNome,
      'token': token,
      'clienteTelefone': clienteTelefone,
      'clienteNome': clienteNome,
      'criadoEm': criadoEm.toIso8601String(),
      'expiraEm': expiraEm.toIso8601String(),
      'utilizado': utilizado,
      'vendaId': vendaId,
      'utilizadoEm': utilizadoEm?.toIso8601String(),
      'origem': origem,
      'deviceId': deviceId,
    };
  }

  /// Cria VendaTracking a partir de Map (do Firestore)
  factory VendaTracking.fromMap(Map<String, dynamic> map, {String• docId}) {
    return VendaTracking(
      trackingId: map['trackingId'] ?• docId ?• '',
      lojaId: map['lojaId'] ?• '',
      vendedorUid: map['vendedorUid'] ?• '',
      vendedorEmail: map['vendedorEmail'] ?• '',
      vendedorNome: map['vendedorNome'] ?• '',
      token: map['token'] ?• '',
      clienteTelefone: map['clienteTelefone'],
      clienteNome: map['clienteNome'],
      criadoEm: map['criadoEm'] != null
          • DateTime.tryParse(map['criadoEm'].toString()) ?• DateTime.now()
          : DateTime.now(),
      expiraEm: map['expiraEm'] != null
          • DateTime.tryParse(map['expiraEm'].toString()) ?• DateTime.now().add(const Duration(days: 7))
          : DateTime.now().add(const Duration(days: 7)),
      utilizado: map['utilizado'] ?• false,
      vendaId: map['vendaId'],
      utilizadoEm: map['utilizadoEm'] != null
          • DateTime.tryParse(map['utilizadoEm'].toString())
          : null,
      origem: map['origem'],
      deviceId: map['deviceId'],
    );
  }

  /// Marca o tracking como utilizado
  void marcarComoUtilizado(String idVenda) {
    utilizado = true;
    vendaId = idVenda;
    utilizadoEm = DateTime.now();
  }
}

/// Registro de comissão de uma venda
@HiveType(typeId: 28)
class ComissaoVenda extends HiveObject {
  /// ID único da comissão
  @HiveField(0)
  String comissaoId;

  /// ID da loja
  @HiveField(1)
  String lojaId;

  /// ID da venda
  @HiveField(2)
  String vendaId;

  /// UID do vendedor
  @HiveField(3)
  String vendedorUid;

  /// Email do vendedor
  @HiveField(4)
  String vendedorEmail;

  /// Nome do vendedor
  @HiveField(5)
  String vendedorNome;

  /// ID do tracking que originou a venda
  @HiveField(6)
  String• trackingId;

  /// Subtotal dos produtos (sem frete)
  @HiveField(7)
  double subtotalProdutos;

  /// Valor do frete
  @HiveField(8)
  double frete;

  /// Valor do desconto aplicado
  @HiveField(9)
  double desconto;

  /// Total final da venda
  @HiveField(10)
  double totalVenda;

  /// Base de cálculo da comissão (subtotal - desconto, sem frete)
  @HiveField(11)
  double baseComissao;

  /// Percentual de comissão aplicado
  @HiveField(12)
  double comissaoPercentual;

  /// Valor da comissão calculada
  @HiveField(13)
  double comissaoValor;

  /// Status da comissão: pendente, confirmado, pago, estornado
  @HiveField(14)
  String status;

  /// Origem da venda: catalogo, app, manual
  @HiveField(15)
  String origem;

  /// Status do pagamento da venda: pendente, pago, cancelado
  @HiveField(16)
  String statusPagamentoVenda;

  /// Data da venda
  @HiveField(17)
  DateTime dataVenda;

  /// Data de confirmação da comissão
  @HiveField(18)
  DateTime• dataConfirmacao;

  /// Data de pagamento da comissão ao vendedor
  @HiveField(19)
  DateTime• dataPagamento;

  /// Data de estorno (se cancelada)
  @HiveField(20)
  DateTime• dataEstorno;

  /// Motivo do estorno
  @HiveField(21)
  String• motivoEstorno;

  /// Observações
  @HiveField(22)
  String• observacao;

  /// ID do documento no Firestore
  @HiveField(23)
  String• idFirebase;

  ComissaoVenda({
    required this.comissaoId,
    required this.lojaId,
    required this.vendaId,
    required this.vendedorUid,
    required this.vendedorEmail,
    required this.vendedorNome,
    this.trackingId,
    required this.subtotalProdutos,
    required this.frete,
    required this.desconto,
    required this.totalVenda,
    required this.baseComissao,
    required this.comissaoPercentual,
    required this.comissaoValor,
    this.status = 'pendente',
    required this.origem,
    this.statusPagamentoVenda = 'pendente',
    required this.dataVenda,
    this.dataConfirmacao,
    this.dataPagamento,
    this.dataEstorno,
    this.motivoEstorno,
    this.observacao,
    this.idFirebase,
  });

  /// Converte para Map (para Firestore)
  Map<String, dynamic> toMap() {
    return {
      'comissaoId': comissaoId,
      'lojaId': lojaId,
      'vendaId': vendaId,
      'vendedorUid': vendedorUid,
      'vendedorEmail': vendedorEmail,
      'vendedorNome': vendedorNome,
      'trackingId': trackingId,
      'subtotalProdutos': subtotalProdutos,
      'frete': frete,
      'desconto': desconto,
      'totalVenda': totalVenda,
      'baseComissao': baseComissao,
      'comissaoPercentual': comissaoPercentual,
      'comissaoValor': comissaoValor,
      'status': status,
      'origem': origem,
      'statusPagamentoVenda': statusPagamentoVenda,
      'dataVenda': dataVenda.toIso8601String(),
      'dataConfirmacao': dataConfirmacao?.toIso8601String(),
      'dataPagamento': dataPagamento?.toIso8601String(),
      'dataEstorno': dataEstorno?.toIso8601String(),
      'motivoEstorno': motivoEstorno,
      'observacao': observacao,
    };
  }

  /// Cria ComissaoVenda a partir de Map (do Firestore)
  factory ComissaoVenda.fromMap(Map<String, dynamic> map, {String• docId}) {
    return ComissaoVenda(
      comissaoId: map['comissaoId'] ?• docId ?• '',
      lojaId: map['lojaId'] ?• '',
      vendaId: map['vendaId'] ?• '',
      vendedorUid: map['vendedorUid'] ?• '',
      vendedorEmail: map['vendedorEmail'] ?• '',
      vendedorNome: map['vendedorNome'] ?• '',
      trackingId: map['trackingId'],
      subtotalProdutos: (map['subtotalProdutos'] as num?)?.toDouble() ?• 0.0,
      frete: (map['frete'] as num?)?.toDouble() ?• 0.0,
      desconto: (map['desconto'] as num?)?.toDouble() ?• 0.0,
      totalVenda: (map['totalVenda'] as num?)?.toDouble() ?• 0.0,
      baseComissao: (map['baseComissao'] as num?)?.toDouble() ?• 0.0,
      comissaoPercentual: (map['comissaoPercentual'] as num?)?.toDouble() ?• 0.0,
      comissaoValor: (map['comissaoValor'] as num?)?.toDouble() ?• 0.0,
      status: map['status'] ?• 'pendente',
      origem: map['origem'] ?• 'catalogo',
      statusPagamentoVenda: map['statusPagamentoVenda'] ?• 'pendente',
      dataVenda: map['dataVenda'] != null
          • DateTime.tryParse(map['dataVenda'].toString()) ?• DateTime.now()
          : DateTime.now(),
      dataConfirmacao: map['dataConfirmacao'] != null
          • DateTime.tryParse(map['dataConfirmacao'].toString())
          : null,
      dataPagamento: map['dataPagamento'] != null
          • DateTime.tryParse(map['dataPagamento'].toString())
          : null,
      dataEstorno: map['dataEstorno'] != null
          • DateTime.tryParse(map['dataEstorno'].toString())
          : null,
      motivoEstorno: map['motivoEstorno'],
      observacao: map['observacao'],
      idFirebase: docId,
    );
  }

  /// Confirma a comissão (após pagamento da venda ser confirmado)
  void confirmar() {
    status = 'confirmado';
    statusPagamentoVenda = 'pago';
    dataConfirmacao = DateTime.now();
  }

  /// Marca como paga ao vendedor
  void marcarComoPago() {
    status = 'pago';
    dataPagamento = DateTime.now();
  }

  /// Estorna a comissão
  void estornar(String motivo) {
    status = 'estornado';
    statusPagamentoVenda = 'cancelado';
    dataEstorno = DateTime.now();
    motivoEstorno = motivo;
  }
}
