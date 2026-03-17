// lib/motor_crescimento_automacoes/models/campanha_automatica.dart
// Modelo de campanha sugerida pela IA de Campanhas Automáticas.

/// Nível de prioridade para ordenação e destaque visual.
enum PrioridadeCampanha {
  alta,
  media,
  baixa,
}

/// Campanha sugerida automaticamente com base em oportunidades.
class CampanhaAutomatica {
  final String id;
  final String lojaId;
  final String tipoCampanha;
  final String entidadeId;
  final String entidadeNome;
  final double percentualDesconto;
  final String codigoCupom;
  final String linkPromocao;
  final String textoPromocional;
  final String status;
  final DateTime criadoEm;
  final DateTime? executadoEm;
  final String origemOportunidade;
  final PrioridadeCampanha prioridade;

  const CampanhaAutomatica({
    required this.id,
    required this.lojaId,
    required this.tipoCampanha,
    required this.entidadeId,
    required this.entidadeNome,
    required this.percentualDesconto,
    required this.codigoCupom,
    required this.linkPromocao,
    required this.textoPromocional,
    this.status = 'sugerida',
    required this.criadoEm,
    this.executadoEm,
    required this.origemOportunidade,
    this.prioridade = PrioridadeCampanha.media,
  });

  /// Badge curto para exibição (Promoção, Urgência, Reposição).
  String get badgeTipo {
    switch (tipoCampanha) {
      case 'promocao':
        return 'Promoção';
      case 'urgencia':
        return 'Urgência';
      case 'combo':
        return 'Combo';
      default:
        return 'Campanha';
    }
  }

  /// Motivo da sugestão em linguagem clara para o lojista.
  String get motivoSugestao {
    switch (tipoCampanha) {
      case 'promocao':
        return 'Produto parado há mais de 30 dias';
      case 'urgencia':
        return 'Estoque baixo – atenção para reposição';
      case 'combo':
        return 'Estoque muito alto';
      default:
        return origemOportunidade;
    }
  }

  /// Dica de impacto visual, sem cálculo complexo.
  String get dicaImpacto {
    switch (tipoCampanha) {
      case 'promocao':
        return 'Esta campanha pode ajudar a girar um produto parado';
      case 'urgencia':
        return 'Destaque o produto antes de acabar o estoque';
      case 'combo':
        return 'Combine com outros produtos para vender mais';
      default:
        return 'Sugestão baseada nas oportunidades da sua loja';
    }
  }
}
