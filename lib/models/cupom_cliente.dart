// lib/models/cupom_cliente.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de cupons disponíveis
enum TipoCupom {
  desconto,        // Desconto em %
  descontoFixo,    // Desconto em R$
  freteGratis,     // Frete grátis
  brinde,          // Brinde (produto grátis)
  premioSurpresa   // Prêmio surpresa
}

/// Cupom ganho pelo cliente na roleta
class CupomCliente {
  final String id;
  final String lojaId;
  final String clienteId;
  final String? clienteNome;
  final String? clienteEmail;
  final String? clienteWhatsApp;

  final TipoCupom tipo;
  final String codigo; // Código único do cupom (ex: ROLETA-ABC123)
  final String titulo; // Ex: "10% de Desconto"
  final String descricao; // Ex: "Válido na próxima compra"

  // Valores
  final double? valorDesconto; // % ou R$ dependendo do tipo
  final String? brindeDescricao; // Se for brinde, descrição do produto
  final String? premioSurpresaDescricao; // Se for prêmio surpresa

  // Controle
  final DateTime dataGanho;
  final DateTime dataValidade; // Geralmente dataGanho + 60 dias
  final bool usado;
  final DateTime? dataUso;
  final String? pedidoId; // ID do pedido onde foi usado

  // Origem
  final String? campanhaId;
  final String? roletaId;

  /// Indicação: cupom do indicador só fica ativo após o amigo usar o dele
  final bool ativo; // default true; false = aguardando amigo usar cupom
  final String? cupomAmigoId; // id do cupom do amigo; quando ele for usado, este ativa

  CupomCliente({
    required this.id,
    required this.lojaId,
    required this.clienteId,
    this.clienteNome,
    this.clienteEmail,
    this.clienteWhatsApp,
    required this.tipo,
    required this.codigo,
    required this.titulo,
    required this.descricao,
    this.valorDesconto,
    this.brindeDescricao,
    this.premioSurpresaDescricao,
    required this.dataGanho,
    required this.dataValidade,
    this.usado = false,
    this.dataUso,
    this.pedidoId,
    this.campanhaId,
    this.roletaId,
    this.ativo = true,
    this.cupomAmigoId,
  });

  /// Verifica se o cupom está expirado
  bool get isExpirado {
    return DateTime.now().isAfter(dataValidade);
  }

  /// Verifica se o cupom está válido para uso
  bool get isValido {
    return !usado && !isExpirado && ativo;
  }

  /// Retorna quantos dias faltam para expirar
  int get diasParaExpirar {
    if (isExpirado) return 0;
    return dataValidade.difference(DateTime.now()).inDays;
  }

  /// Descrição do tipo de cupom
  String get tipoDescricao {
    switch (tipo) {
      case TipoCupom.desconto:
        return 'Desconto de ${valorDesconto?.toStringAsFixed(0)}%';
      case TipoCupom.descontoFixo:
        return 'Desconto de R\$ ${valorDesconto?.toStringAsFixed(2)}';
      case TipoCupom.freteGratis:
        return 'Frete Grátis';
      case TipoCupom.brinde:
        return 'Brinde: ${brindeDescricao ?? "Produto grátis"}';
      case TipoCupom.premioSurpresa:
        return 'Prêmio Surpresa: ${premioSurpresaDescricao ?? "Aguarde!"}';
    }
  }

  /// Instruções de uso
  String get instrucoes {
    switch (tipo) {
      case TipoCupom.desconto:
      case TipoCupom.descontoFixo:
        return 'O desconto será aplicado automaticamente na próxima compra.';
      case TipoCupom.freteGratis:
        return 'O frete será zerado automaticamente na próxima compra.';
      case TipoCupom.brinde:
        return 'O brinde será adicionado automaticamente ao seu pedido.';
      case TipoCupom.premioSurpresa:
        return 'O prêmio será revelado ao finalizar sua próxima compra.';
    }
  }

  factory CupomCliente.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    // Parse tipo
    final tipoStr = data['tipo'] as String? ?? 'desconto';
    TipoCupom tipo;
    switch (tipoStr) {
      case 'descontoFixo':
        tipo = TipoCupom.descontoFixo;
        break;
      case 'freteGratis':
        tipo = TipoCupom.freteGratis;
        break;
      case 'brinde':
        tipo = TipoCupom.brinde;
        break;
      case 'premioSurpresa':
        tipo = TipoCupom.premioSurpresa;
        break;
      default:
        tipo = TipoCupom.desconto;
    }

    return CupomCliente(
      id: doc.id,
      lojaId: data['lojaId'] as String? ?? '',
      clienteId: data['clienteId'] as String? ?? '',
      clienteNome: data['clienteNome'] as String?,
      clienteEmail: data['clienteEmail'] as String?,
      clienteWhatsApp: data['clienteWhatsApp'] as String?,
      tipo: tipo,
      codigo: data['codigo'] as String? ?? '',
      titulo: data['titulo'] as String? ?? '',
      descricao: data['descricao'] as String? ?? '',
      valorDesconto: (data['valorDesconto'] as num?)?.toDouble(),
      brindeDescricao: data['brindeDescricao'] as String?,
      premioSurpresaDescricao: data['premioSurpresaDescricao'] as String?,
      dataGanho: (data['dataGanho'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dataValidade: (data['dataValidade'] as Timestamp?)?.toDate() ??
                    DateTime.now().add(const Duration(days: 60)),
      usado: data['usado'] as bool? ?? false,
      dataUso: (data['dataUso'] as Timestamp?)?.toDate(),
      pedidoId: data['pedidoId'] as String?,
      campanhaId: data['campanhaId'] as String?,
      roletaId: data['roletaId'] as String?,
      ativo: data['ativo'] as bool? ?? true,
      cupomAmigoId: data['cupomAmigoId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    // Converte tipo para string
    String tipoStr;
    switch (tipo) {
      case TipoCupom.desconto:
        tipoStr = 'desconto';
        break;
      case TipoCupom.descontoFixo:
        tipoStr = 'descontoFixo';
        break;
      case TipoCupom.freteGratis:
        tipoStr = 'freteGratis';
        break;
      case TipoCupom.brinde:
        tipoStr = 'brinde';
        break;
      case TipoCupom.premioSurpresa:
        tipoStr = 'premioSurpresa';
        break;
    }

    return {
      'lojaId': lojaId,
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'clienteEmail': clienteEmail,
      'clienteWhatsApp': clienteWhatsApp,
      'tipo': tipoStr,
      'codigo': codigo,
      'titulo': titulo,
      'descricao': descricao,
      'valorDesconto': valorDesconto,
      'brindeDescricao': brindeDescricao,
      'premioSurpresaDescricao': premioSurpresaDescricao,
      'dataGanho': Timestamp.fromDate(dataGanho),
      'dataValidade': Timestamp.fromDate(dataValidade),
      'usado': usado,
      'dataUso': dataUso != null ? Timestamp.fromDate(dataUso!) : null,
      'pedidoId': pedidoId,
      'campanhaId': campanhaId,
      'roletaId': roletaId,
      'ativo': ativo,
      'cupomAmigoId': cupomAmigoId,
    };
  }

  /// Cria uma cópia com campos atualizados
  CupomCliente copyWith({
    bool? usado,
    DateTime? dataUso,
    String? pedidoId,
    bool? ativo,
    String? cupomAmigoId,
  }) {
    return CupomCliente(
      id: id,
      lojaId: lojaId,
      clienteId: clienteId,
      clienteNome: clienteNome,
      clienteEmail: clienteEmail,
      clienteWhatsApp: clienteWhatsApp,
      tipo: tipo,
      codigo: codigo,
      titulo: titulo,
      descricao: descricao,
      valorDesconto: valorDesconto,
      brindeDescricao: brindeDescricao,
      premioSurpresaDescricao: premioSurpresaDescricao,
      dataGanho: dataGanho,
      dataValidade: dataValidade,
      usado: usado ?? this.usado,
      dataUso: dataUso ?? this.dataUso,
      pedidoId: pedidoId ?? this.pedidoId,
      campanhaId: campanhaId,
      roletaId: roletaId,
      ativo: ativo ?? this.ativo,
      cupomAmigoId: cupomAmigoId ?? this.cupomAmigoId,
    );
  }
}
