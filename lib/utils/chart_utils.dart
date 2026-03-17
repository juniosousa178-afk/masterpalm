// lib/utils/chart_utils.dart
// Utilitários para gráficos fl_chart - evita crashes por interval = 0

import 'dart:math' as math;

/// Calcula um intervalo seguro para eixos de gráficos.
///
/// Garante que o valor retornado NUNCA seja 0, NaN ou infinito.
///
/// [min] - Valor mínimo do eixo
/// [max] - Valor máximo do eixo
/// [targetLines] - Quantidade desejada de linhas de grade (default: 5)
/// [minInterval] - Intervalo mínimo garantido (default: 1.0)
///
/// Retorna um intervalo seguro > 0 para uso em FlGridData.horizontalInterval
/// ou FlGridData.verticalInterval.
double safeInterval({
  required double min,
  required double max,
  int targetLines = 5,
  double minInterval = 1.0,
}) {
  // Garantir minInterval > 0
  if (minInterval <= 0 || minInterval.isNaN || minInterval.isInfinite) {
    minInterval = 1.0;
  }

  // Garantir targetLines > 0
  if (targetLines <= 0) {
    targetLines = 5;
  }

  // Calcular range
  final range = max - min;

  // Se range é inválido, retorna minInterval
  if (range <= 0 || range.isNaN || range.isInfinite) {
    return minInterval;
  }

  // Calcular intervalo bruto
  double interval = range / targetLines;

  // Se intervalo é inválido, retorna minInterval
  if (interval <= 0 || interval.isNaN || interval.isInfinite) {
    return minInterval;
  }

  // Arredondar para um número "bonito" (opcional, melhora visualização)
  interval = _roundToNiceNumber(interval);

  // Garantir mínimo
  return math.max(interval, minInterval);
}

/// Arredonda para um número "bonito" para eixos de gráfico.
/// Ex: 0.7 → 1, 3.2 → 5, 17 → 20, 230 → 250
double _roundToNiceNumber(double value) {
  if (value <= 0 || value.isNaN || value.isInfinite) return 1.0;

  // Encontrar ordem de magnitude
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();

  // Normalizar para 1-10
  final normalized = value / magnitude;

  // Arredondar para número bonito
  double nice;
  if (normalized <= 1.5) {
    nice = 1;
  } else if (normalized <= 3) {
    nice = 2;
  } else if (normalized <= 7) {
    nice = 5;
  } else {
    nice = 10;
  }

  return nice * magnitude;
}

/// Calcula um maxY seguro para gráficos.
///
/// Garante que maxY > 0 mesmo quando todos os dados são zero.
/// Adiciona margem superior para visualização.
///
/// [values] - Lista de valores dos dados
/// [marginPercent] - Margem superior em percentual (default: 20%)
/// [minValue] - Valor mínimo garantido (default: 100)
double safeMaxY(
  List<double> values, {
  double marginPercent = 0.2,
  double minValue = 100.0,
}) {
  if (values.isEmpty) return minValue;

  // Encontrar máximo
  double maxVal = values.reduce((a, b) => math.max(a, b));

  // Se máximo é inválido, usar minValue
  if (maxVal <= 0 || maxVal.isNaN || maxVal.isInfinite) {
    return minValue;
  }

  // Adicionar margem
  return maxVal * (1 + marginPercent);
}
