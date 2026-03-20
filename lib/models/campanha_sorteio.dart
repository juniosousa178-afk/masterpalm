// lib/models/campanha_sorteio.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CampanhaSorteio {
  final String id;
  final String lojaId;
  final String titulo;
  final String• descricao;
  final double valorMinimo; // valor mínimo da compra para ganhar número
  final String status; // "aberta", "encerrada"
  final DateTime• dataInicio;
  final DateTime• dataFim;
  final String• premioDescricao;

  // ✅ NOVO: Controle de frequência de prêmios
  final int frequenciaPremio; // A cada X vendas, 1 sai premiada (ex: 10)
  final int totalVendas; // Total de vendas desde o início
  final int vendasDesdePremio; // Vendas desde o último prêmio

  // ✅ NOVO: Configuração da roleta
  final List<Map<String, dynamic>> premios; // Lista de prêmios disponíveis

  CampanhaSorteio({
    required this.id,
    required this.lojaId,
    required this.titulo,
    this.descricao,
    required this.valorMinimo,
    required this.status,
    this.dataInicio,
    this.dataFim,
    this.premioDescricao,
    this.frequenciaPremio = 10, // Padrão: a cada 10 vendas
    this.totalVendas = 0,
    this.vendasDesdePremio = 0,
    this.premios = const [],
  });

  factory CampanhaSorteio.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?• {};
    return CampanhaSorteio(
      id: doc.id,
      lojaId: data['lojaId'] as String• ?• '',
      titulo: data['titulo'] as String• ?• data['name'] as String• ?• 'Campanha',
      descricao: data['descricao'] as String?,
      valorMinimo: (data['valorMinimo'] as num?)?.toDouble() ?• 0.0,
      status: data['status'] as String• ?• 'aberta',
      dataInicio: (data['dataInicio'] as Timestamp?)?.toDate(),
      dataFim: (data['dataFim'] as Timestamp?)?.toDate(),
      premioDescricao: data['premioDescricao'] as String?,
      frequenciaPremio: data['frequenciaPremio'] as int• ?• 10,
      totalVendas: data['totalVendas'] as int• ?• 0,
      vendasDesdePremio: data['vendasDesdePremio'] as int• ?• 0,
      premios: List<Map<String, dynamic>>.from(data['premios'] ?• []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lojaId': lojaId,
      'titulo': titulo,
      'descricao': descricao,
      'valorMinimo': valorMinimo,
      'status': status,
      'dataInicio': dataInicio != null • Timestamp.fromDate(dataInicio!) : null,
      'dataFim': dataFim != null • Timestamp.fromDate(dataFim!) : null,
      'premioDescricao': premioDescricao,
      'frequenciaPremio': frequenciaPremio,
      'totalVendas': totalVendas,
      'vendasDesdePremio': vendasDesdePremio,
      'premios': premios,
    };
  }

  /// Verifica se a próxima venda deve ganhar prêmio
  bool get proximaVendaGanhaPremio {
    return vendasDesdePremio >= frequenciaPremio;
  }

  /// Incrementa contador de vendas
  CampanhaSorteio incrementarVenda({bool premiada = false}) {
    return CampanhaSorteio(
      id: id,
      lojaId: lojaId,
      titulo: titulo,
      descricao: descricao,
      valorMinimo: valorMinimo,
      status: status,
      dataInicio: dataInicio,
      dataFim: dataFim,
      premioDescricao: premioDescricao,
      frequenciaPremio: frequenciaPremio,
      totalVendas: totalVendas + 1,
      vendasDesdePremio: premiada • 0 : vendasDesdePremio + 1,
      premios: premios,
    );
  }
}

class TicketSorteio {
  final String id;
  final String campanhaId;
  final String lojaId;
  final String numero; // "53827"
  final String• clienteId;
  final String• clienteNome;
  final String• vendaId;
  final DateTime createdAt;

  TicketSorteio({
    required this.id,
    required this.campanhaId,
    required this.lojaId,
    required this.numero,
    this.clienteId,
    this.clienteNome,
    this.vendaId,
    required this.createdAt,
  });

  factory TicketSorteio.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?• {};
    return TicketSorteio(
      id: doc.id,
      campanhaId: data['campanhaId'] as String• ?• '',
      lojaId: data['lojaId'] as String• ?• '',
      numero: data['numero'] as String• ?• '',
      clienteId: data['clienteId'] as String?,
      clienteNome: data['clienteNome'] as String?,
      vendaId: data['vendaId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?• DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'campanhaId': campanhaId,
      'lojaId': lojaId,
      'numero': numero,
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'vendaId': vendaId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
