// lib/models/cupom.dart
// Modelo completo de cupom com todas as regras de negócio

import 'package:cloud_firestore/cloud_firestore.dart';

List<String> _cupomProdutoIdsFromData(dynamic v) {
  if (v == null) return [];
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  final s = v.toString().trim();
  return s.isEmpty ? [] : [s];
}

class Cupom {
  final String id;
  final String codigo;
  final String nome;
  final double valor;
  final String tipo; // 'fixo' ou 'percentual'
  final String aplicarEm; // 'produtos', 'total', 'frete'
  /// Se não vazio, o desconto só incide sobre linhas do carrinho cujo id está na lista.
  final List<String> produtoIds;
  final bool freteGratis;
  final bool usoUnico; // Uso único por cliente
  final bool usoUnicoGlobal; // Uso único global (somente uma pessoa pode usar)
  final String? clienteId; // Se preenchido, somente este cliente pode usar (vale-compra)
  final bool ativo;
  final List<String> usadosPor; // IDs dos clientes que já usaram
  final DateTime? dataInicio;
  final DateTime? dataFim;
  final double? valorMinimo; // Valor mínimo do pedido para usar o cupom
  final int? qtdMaximaUsos; // Quantidade máxima de usos (null = ilimitado)
  final int qtdUsosAtuais; // Quantidade de vezes que foi usado
  final DateTime criadoEm;
  final DateTime? atualizadoEm;

  Cupom({
    required this.id,
    required this.codigo,
    required this.nome,
    required this.valor,
    required this.tipo,
    this.aplicarEm = 'total',
    this.produtoIds = const [],
    this.freteGratis = false,
    this.usoUnico = false,
    this.usoUnicoGlobal = false,
    this.clienteId,
    this.ativo = true,
    this.usadosPor = const [],
    this.dataInicio,
    this.dataFim,
    this.valorMinimo,
    this.qtdMaximaUsos,
    this.qtdUsosAtuais = 0,
    required this.criadoEm,
    this.atualizadoEm,
  });

  // Verifica se o cupom pode ser usado por um cliente específico
  bool podeSerUsado(String clienteId, double valorPedido) {
    // Inativo
    if (!ativo) return false;

    // Fora da validade
    final agora = DateTime.now();
    if (dataInicio != null && agora.isBefore(dataInicio!)) return false;
    if (dataFim != null && agora.isAfter(dataFim!)) return false;

    // Valor mínimo
    if (valorMinimo != null && valorPedido < valorMinimo!) return false;

    // Limite de usos atingido
    if (qtdMaximaUsos != null && qtdUsosAtuais >= qtdMaximaUsos!) return false;

    // Cupom específico de cliente (vale-compra)
    if (this.clienteId != null && this.clienteId != clienteId) return false;

    // Uso único global
    if (usoUnicoGlobal && qtdUsosAtuais > 0) return false;

    // Uso único por cliente
    if (usoUnico && usadosPor.contains(clienteId)) return false;

    return true;
  }

  // Calcula o valor do desconto
  double calcularDesconto(double valorBase) {
    if (tipo == 'percentual') {
      return (valorBase * valor / 100).clamp(0, valorBase);
    } else {
      return valor.clamp(0, valorBase);
    }
  }

  // Factory from Firestore
  factory Cupom.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Cupom(
      id: doc.id,
      codigo: data['codigo'] ?? '',
      nome: data['nome'] ?? '',
      valor: (data['valor'] ?? 0).toDouble(),
      tipo: data['tipo'] ?? 'fixo',
      aplicarEm: data['aplicarEm'] ?? 'total',
      produtoIds: _cupomProdutoIdsFromData(data['produtoIds'] ?? data['produtoId']),
      freteGratis: data['freteGratis'] ?? false,
      usoUnico: data['usoUnico'] ?? false,
      usoUnicoGlobal: data['usoUnicoGlobal'] ?? false,
      clienteId: data['clienteId'],
      ativo: data['ativo'] ?? true,
      usadosPor: List<String>.from(data['usadosPor'] ?? []),
      dataInicio: data['dataInicio'] != null
          ? (data['dataInicio'] as Timestamp).toDate()
          : null,
      dataFim: data['dataFim'] != null
          ? (data['dataFim'] as Timestamp).toDate()
          : null,
      valorMinimo: data['valorMinimo']?.toDouble(),
      qtdMaximaUsos: data['qtdMaximaUsos'],
      qtdUsosAtuais: data['qtdUsosAtuais'] ?? 0,
      criadoEm: (data['criadoEm'] as Timestamp).toDate(),
      atualizadoEm: data['atualizadoEm'] != null
          ? (data['atualizadoEm'] as Timestamp).toDate()
          : null,
    );
  }

  // To Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'codigo': codigo,
      'nome': nome,
      'valor': valor,
      'tipo': tipo,
      'aplicarEm': aplicarEm,
      if (produtoIds.isNotEmpty) 'produtoIds': produtoIds,
      'freteGratis': freteGratis,
      'usoUnico': usoUnico,
      'usoUnicoGlobal': usoUnicoGlobal,
      'clienteId': clienteId,
      'ativo': ativo,
      'usadosPor': usadosPor,
      'dataInicio': dataInicio,
      'dataFim': dataFim,
      'valorMinimo': valorMinimo,
      'qtdMaximaUsos': qtdMaximaUsos,
      'qtdUsosAtuais': qtdUsosAtuais,
      'criadoEm': Timestamp.fromDate(criadoEm),
      'atualizadoEm': Timestamp.fromDate(atualizadoEm ?? DateTime.now()),
    };
  }

  // Copy with
  Cupom copyWith({
    String? id,
    String? codigo,
    String? nome,
    double? valor,
    String? tipo,
    String? aplicarEm,
    List<String>? produtoIds,
    bool? freteGratis,
    bool? usoUnico,
    bool? usoUnicoGlobal,
    String? clienteId,
    bool? ativo,
    List<String>? usadosPor,
    DateTime? dataInicio,
    DateTime? dataFim,
    double? valorMinimo,
    int? qtdMaximaUsos,
    int? qtdUsosAtuais,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
  }) {
    return Cupom(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nome: nome ?? this.nome,
      valor: valor ?? this.valor,
      tipo: tipo ?? this.tipo,
      aplicarEm: aplicarEm ?? this.aplicarEm,
      produtoIds: produtoIds ?? this.produtoIds,
      freteGratis: freteGratis ?? this.freteGratis,
      usoUnico: usoUnico ?? this.usoUnico,
      usoUnicoGlobal: usoUnicoGlobal ?? this.usoUnicoGlobal,
      clienteId: clienteId ?? this.clienteId,
      ativo: ativo ?? this.ativo,
      usadosPor: usadosPor ?? this.usadosPor,
      dataInicio: dataInicio ?? this.dataInicio,
      dataFim: dataFim ?? this.dataFim,
      valorMinimo: valorMinimo ?? this.valorMinimo,
      qtdMaximaUsos: qtdMaximaUsos ?? this.qtdMaximaUsos,
      qtdUsosAtuais: qtdUsosAtuais ?? this.qtdUsosAtuais,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }
}
