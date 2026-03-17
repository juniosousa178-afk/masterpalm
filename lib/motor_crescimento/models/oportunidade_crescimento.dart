// lib/motor_crescimento/models/oportunidade_crescimento.dart
// Modelo de oportunidade detectada pelo Motor de Crescimento IA (Etapa 1).

/// Tipo de oportunidade detectada.
enum TipoOportunidade {
  produtoParado,
  estoqueBaixo,
}

/// Oportunidade de crescimento detectada pelo motor.
/// Usado apenas para exibição no painel (Etapa 1).
class OportunidadeCrescimento {
  final String id;
  final TipoOportunidade tipo;
  final String titulo;
  final String descricao;
  final int prioridade; // 1–5 (5 = mais urgente)
  final String entidadeId;
  final String entidadeNome;
  final String metricaPrincipal;
  final Map<String, dynamic> detalhes;
  final DateTime criadoEm;

  const OportunidadeCrescimento({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.prioridade,
    required this.entidadeId,
    required this.entidadeNome,
    required this.metricaPrincipal,
    this.detalhes = const {},
    required this.criadoEm,
  });

  String get tipoLabel {
    switch (tipo) {
      case TipoOportunidade.produtoParado:
        return 'Produto parado';
      case TipoOportunidade.estoqueBaixo:
        return 'Estoque baixo';
    }
  }
}
