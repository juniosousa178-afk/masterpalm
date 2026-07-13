// Score determinístico de probabilidade de recuperação de carrinho abandonado.
// Sem IA. Regras M3.8 S1-H7.

import 'package:flutter/material.dart';

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
        return 'Alta recuperação';
      case RecuperacaoProbabilidade.media:
        return 'Média recuperação';
      case RecuperacaoProbabilidade.baixa:
        return 'Baixa recuperação';
    }
  }

  /// Badge curto para lista (🟢 / 🟡 / 🔴).
  String get emojiBadge {
    switch (categoria) {
      case RecuperacaoProbabilidade.alta:
        return '🟢';
      case RecuperacaoProbabilidade.media:
        return '🟡';
      case RecuperacaoProbabilidade.baixa:
        return '🔴';
    }
  }

  Color get badgeColor {
    switch (categoria) {
      case RecuperacaoProbabilidade.alta:
        return const Color(0xFF22C55E);
      case RecuperacaoProbabilidade.media:
        return const Color(0xFFF59E0B);
      case RecuperacaoProbabilidade.baixa:
        return const Color(0xFFEF4444);
    }
  }
}

/// Regras determinísticas (S1-H7):
/// - Tempo abandonado
/// - Valor do carrinho
/// - Quantidade de itens
/// - Cliente recorrente
/// - Tem WhatsApp / telefone
/// - Tem e-mail
RecuperacaoScoreResult calcularProbabilidadeRecuperacao({
  required Duration tempoAbandonado,
  required double valorCarrinho,
  int quantidadeItens = 0,
  bool clienteRecorrente = false,
  bool temWhatsapp = false,
  bool temEmail = false,
  int visitasCatalogo = 0,
  int retornosCatalogo = 0,
}) {
  var pontos = 0;
  final motivos = <String>[];

  final horas = tempoAbandonado.inHours;
  if (horas <= 6) {
    pontos += 30;
    motivos.add('abandonado há ≤6h');
  } else if (horas <= 24) {
    pontos += 20;
    motivos.add('abandonado há ≤24h');
  } else if (horas <= 72) {
    pontos += 8;
    motivos.add('abandonado há ≤72h');
  } else {
    motivos.add('abandonado há >72h');
  }

  if (valorCarrinho >= 300) {
    pontos += 22;
    motivos.add('carrinho ≥ R\$ 300');
  } else if (valorCarrinho >= 100) {
    pontos += 14;
    motivos.add('carrinho ≥ R\$ 100');
  } else if (valorCarrinho > 0) {
    pontos += 6;
    motivos.add('carrinho com valor');
  }

  if (quantidadeItens >= 5) {
    pontos += 12;
    motivos.add('≥5 itens');
  } else if (quantidadeItens >= 2) {
    pontos += 8;
    motivos.add('≥2 itens');
  } else if (quantidadeItens == 1) {
    pontos += 3;
    motivos.add('1 item');
  }

  if (clienteRecorrente) {
    pontos += 15;
    motivos.add('cliente recorrente');
  }

  if (temWhatsapp) {
    pontos += 10;
    motivos.add('tem WhatsApp');
  }

  if (temEmail) {
    pontos += 10;
    motivos.add('tem e-mail');
  }

  final engajamento = visitasCatalogo + retornosCatalogo;
  if (engajamento >= 3) {
    pontos += 10;
    motivos.add('múltiplas visitas/retornos');
  } else if (engajamento >= 1) {
    pontos += 5;
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
