// lib/models/comissao_config.dart
// Modelo para configuração de comissões de vendedores

import 'package:hive/hive.dart';

part 'comissao_config.g.dart';

@HiveType(typeId: 25)
class ComissaoConfig extends HiveObject {
  /// ID da loja
  @HiveField(0)
  String lojaId;

  /// Percentual de comissão global padrão (ex: 5.0 = 5%)
  @HiveField(1)
  double comissaoGlobalPercent;

  /// Se a comissão só é paga após pagamento confirmado
  @HiveField(2)
  bool apenasAposPagamentoConfirmado;

  /// Se exclui frete da base de cálculo
  @HiveField(3)
  bool excluirFreteDaBase;

  /// Se exclui desconto da base de cálculo (já reduz a base)
  @HiveField(4)
  bool descontoReduzBase;

  /// Expiração do tracking em dias (padrão: 7)
  @HiveField(5)
  int trackingExpiracaoDias;

  /// Regra de atribuição: 'ultimo_clique' ou 'primeiro_clique'
  @HiveField(6)
  String regraAtribuicao;

  /// Bônus por meta batida (ex: bateu 100% = +1%)
  @HiveField(7)
  double bonusMetaBatida100;

  /// Bônus por meta superada (ex: bateu 150% = +2%)
  @HiveField(8)
  double bonusMetaBatida150;

  /// Comissão mínima por venda em R$
  @HiveField(9)
  double comissaoMinimaValor;

  /// Comissão máxima por venda em R$
  @HiveField(10)
  double comissaoMaximaValor;

  /// Se habilita estorno automático em vendas canceladas
  @HiveField(11)
  bool estornoAutomaticoEmCancelamento;

  /// Data de criação
  @HiveField(12)
  DateTime criadoEm;

  /// Data de atualização
  @HiveField(13)
  DateTime atualizadoEm;

  /// ID do documento no Firestore
  @HiveField(14)
  String• idFirebase;

  ComissaoConfig({
    required this.lojaId,
    this.comissaoGlobalPercent = 5.0,
    this.apenasAposPagamentoConfirmado = true,
    this.excluirFreteDaBase = true,
    this.descontoReduzBase = true,
    this.trackingExpiracaoDias = 7,
    this.regraAtribuicao = 'ultimo_clique',
    this.bonusMetaBatida100 = 1.0,
    this.bonusMetaBatida150 = 2.0,
    this.comissaoMinimaValor = 0.0,
    this.comissaoMaximaValor = 0.0, // 0 = sem limite
    this.estornoAutomaticoEmCancelamento = true,
    DateTime• criadoEm,
    DateTime• atualizadoEm,
    this.idFirebase,
  })  : criadoEm = criadoEm ?• DateTime.now(),
        atualizadoEm = atualizadoEm ?• DateTime.now();

  /// Converte para Map (para Firestore)
  Map<String, dynamic> toMap() {
    return {
      'lojaId': lojaId,
      'comissaoGlobalPercent': comissaoGlobalPercent,
      'apenasAposPagamentoConfirmado': apenasAposPagamentoConfirmado,
      'excluirFreteDaBase': excluirFreteDaBase,
      'descontoReduzBase': descontoReduzBase,
      'trackingExpiracaoDias': trackingExpiracaoDias,
      'regraAtribuicao': regraAtribuicao,
      'bonusMetaBatida100': bonusMetaBatida100,
      'bonusMetaBatida150': bonusMetaBatida150,
      'comissaoMinimaValor': comissaoMinimaValor,
      'comissaoMaximaValor': comissaoMaximaValor,
      'estornoAutomaticoEmCancelamento': estornoAutomaticoEmCancelamento,
      'criadoEm': criadoEm.toIso8601String(),
      'atualizadoEm': DateTime.now().toIso8601String(),
    };
  }

  /// Cria ComissaoConfig a partir de Map (do Firestore)
  factory ComissaoConfig.fromMap(Map<String, dynamic> map, {String• docId}) {
    return ComissaoConfig(
      lojaId: map['lojaId'] ?• '',
      comissaoGlobalPercent: (map['comissaoGlobalPercent'] as num?)?.toDouble() ?• 5.0,
      apenasAposPagamentoConfirmado: map['apenasAposPagamentoConfirmado'] ?• true,
      excluirFreteDaBase: map['excluirFreteDaBase'] ?• true,
      descontoReduzBase: map['descontoReduzBase'] ?• true,
      trackingExpiracaoDias: (map['trackingExpiracaoDias'] as num?)?.toInt() ?• 7,
      regraAtribuicao: map['regraAtribuicao'] ?• 'ultimo_clique',
      bonusMetaBatida100: (map['bonusMetaBatida100'] as num?)?.toDouble() ?• 1.0,
      bonusMetaBatida150: (map['bonusMetaBatida150'] as num?)?.toDouble() ?• 2.0,
      comissaoMinimaValor: (map['comissaoMinimaValor'] as num?)?.toDouble() ?• 0.0,
      comissaoMaximaValor: (map['comissaoMaximaValor'] as num?)?.toDouble() ?• 0.0,
      estornoAutomaticoEmCancelamento: map['estornoAutomaticoEmCancelamento'] ?• true,
      criadoEm: map['criadoEm'] != null
          • DateTime.tryParse(map['criadoEm'].toString()) ?• DateTime.now()
          : DateTime.now(),
      atualizadoEm: map['atualizadoEm'] != null
          • DateTime.tryParse(map['atualizadoEm'].toString()) ?• DateTime.now()
          : DateTime.now(),
      idFirebase: docId,
    );
  }

  ComissaoConfig copyWith({
    String• lojaId,
    double• comissaoGlobalPercent,
    bool• apenasAposPagamentoConfirmado,
    bool• excluirFreteDaBase,
    bool• descontoReduzBase,
    int• trackingExpiracaoDias,
    String• regraAtribuicao,
    double• bonusMetaBatida100,
    double• bonusMetaBatida150,
    double• comissaoMinimaValor,
    double• comissaoMaximaValor,
    bool• estornoAutomaticoEmCancelamento,
    DateTime• criadoEm,
    DateTime• atualizadoEm,
    String• idFirebase,
  }) {
    return ComissaoConfig(
      lojaId: lojaId ?• this.lojaId,
      comissaoGlobalPercent: comissaoGlobalPercent ?• this.comissaoGlobalPercent,
      apenasAposPagamentoConfirmado: apenasAposPagamentoConfirmado ?• this.apenasAposPagamentoConfirmado,
      excluirFreteDaBase: excluirFreteDaBase ?• this.excluirFreteDaBase,
      descontoReduzBase: descontoReduzBase ?• this.descontoReduzBase,
      trackingExpiracaoDias: trackingExpiracaoDias ?• this.trackingExpiracaoDias,
      regraAtribuicao: regraAtribuicao ?• this.regraAtribuicao,
      bonusMetaBatida100: bonusMetaBatida100 ?• this.bonusMetaBatida100,
      bonusMetaBatida150: bonusMetaBatida150 ?• this.bonusMetaBatida150,
      comissaoMinimaValor: comissaoMinimaValor ?• this.comissaoMinimaValor,
      comissaoMaximaValor: comissaoMaximaValor ?• this.comissaoMaximaValor,
      estornoAutomaticoEmCancelamento: estornoAutomaticoEmCancelamento ?• this.estornoAutomaticoEmCancelamento,
      criadoEm: criadoEm ?• this.criadoEm,
      atualizadoEm: atualizadoEm ?• DateTime.now(),
      idFirebase: idFirebase ?• this.idFirebase,
    );
  }
}

/// Configuração de comissão específica por vendedor
@HiveType(typeId: 26)
class ComissaoVendedor extends HiveObject {
  /// ID da loja
  @HiveField(0)
  String lojaId;

  /// UID do vendedor (Firebase Auth)
  @HiveField(1)
  String vendedorUid;

  /// Email do vendedor
  @HiveField(2)
  String vendedorEmail;

  /// Nome do vendedor
  @HiveField(3)
  String vendedorNome;

  /// Percentual de comissão específico (null = usa global)
  @HiveField(4)
  double• comissaoPercentual;

  /// Se está ativo para receber comissões
  @HiveField(5)
  bool ativo;

  /// Data de criação
  @HiveField(6)
  DateTime criadoEm;

  /// Data de atualização
  @HiveField(7)
  DateTime atualizadoEm;

  /// ID do documento no Firestore
  @HiveField(8)
  String• idFirebase;

  ComissaoVendedor({
    required this.lojaId,
    required this.vendedorUid,
    required this.vendedorEmail,
    required this.vendedorNome,
    this.comissaoPercentual,
    this.ativo = true,
    DateTime• criadoEm,
    DateTime• atualizadoEm,
    this.idFirebase,
  })  : criadoEm = criadoEm ?• DateTime.now(),
        atualizadoEm = atualizadoEm ?• DateTime.now();

  /// Converte para Map (para Firestore)
  Map<String, dynamic> toMap() {
    return {
      'lojaId': lojaId,
      'vendedorUid': vendedorUid,
      'vendedorEmail': vendedorEmail,
      'vendedorNome': vendedorNome,
      'comissaoPercentual': comissaoPercentual,
      'ativo': ativo,
      'criadoEm': criadoEm.toIso8601String(),
      'atualizadoEm': DateTime.now().toIso8601String(),
    };
  }

  /// Cria ComissaoVendedor a partir de Map (do Firestore)
  factory ComissaoVendedor.fromMap(Map<String, dynamic> map, {String• docId}) {
    return ComissaoVendedor(
      lojaId: map['lojaId'] ?• '',
      vendedorUid: map['vendedorUid'] ?• '',
      vendedorEmail: map['vendedorEmail'] ?• '',
      vendedorNome: map['vendedorNome'] ?• '',
      comissaoPercentual: (map['comissaoPercentual'] as num?)?.toDouble(),
      ativo: map['ativo'] ?• true,
      criadoEm: map['criadoEm'] != null
          • DateTime.tryParse(map['criadoEm'].toString()) ?• DateTime.now()
          : DateTime.now(),
      atualizadoEm: map['atualizadoEm'] != null
          • DateTime.tryParse(map['atualizadoEm'].toString()) ?• DateTime.now()
          : DateTime.now(),
      idFirebase: docId,
    );
  }
}
