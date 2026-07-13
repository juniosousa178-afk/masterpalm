// Score determinístico de probabilidade de recuperação de carrinho abandonado.
// Sem IA.

enum RecuperacaoProbabilidade { alta, media, baixa }

class RecuperacaoScoreResult {
  const RecuperacaoScoreResult({
    required this.categoria,
    required this.pontos,
    required this.motivos,
  });

  final RecuperacaoProbabilidade categoria;
  final int pontos;
  final List<String> motivos;

  String get label {
    switch (categoria) {
      case RecuperacaoProbabilidade.alta:
        return 'Alta';
      case RecuperacaoProbabilidade.media:
        return 'Média';
      case RecuperacaoProbabilidade.baixa:
        return 'Baixa';
    }
  }
}

/// Regras:
/// - Tempo abandonado curto → +pontos
/// - Valor do carrinho alto → +pontos
/// - Visitas / retornos ao catálogo → +pontos
RecuperacaoScoreResult calcularProbabilidadeRecuperacao({
  required Duration tempoAbandonado,
  required double valorCarrinho,
  int visitasCatalogo = 0,
  int retornosCatalogo = 0,
}) {
  var pontos = 0;
  final motivos = <String>[];

  final horas = tempoAbandonado.inHours;
  if (horas <= 6) {
    pontos += 40;
    motivos.add('abandonado há ≤6h');
  } else if (horas <= 24) {
    pontos += 25;
    motivos.add('abandonado há ≤24h');
  } else if (horas <= 72) {
    pontos += 10;
    motivos.add('abandonado há ≤72h');
  } else {
    motivos.add('abandonado há >72h');
  }

  if (valorCarrinho >= 300) {
    pontos += 30;
    motivos.add('carrinho ≥ R\$ 300');
  } else if (valorCarrinho >= 100) {
    pontos += 20;
    motivos.add('carrinho ≥ R\$ 100');
  } else if (valorCarrinho > 0) {
    pontos += 8;
    motivos.add('carrinho com valor');
  }

  final engajamento = visitasCatalogo + retornosCatalogo;
  if (engajamento >= 3) {
    pontos += 30;
    motivos.add('múltiplas visitas/retornos');
  } else if (engajamento >= 1) {
    pontos += 15;
    motivos.add('retornou ao catálogo');
  }

  final RecuperacaoProbabilidade cat;
  if (pontos >= 60) {
    cat = RecuperacaoProbabilidade.alta;
  } else if (pontos >= 30) {
    cat = RecuperacaoProbabilidade.media;
  } else {
    cat = RecuperacaoProbabilidade.baixa;
  }

  return RecuperacaoScoreResult(
    categoria: cat,
    pontos: pontos,
    motivos: motivos,
  );
}
