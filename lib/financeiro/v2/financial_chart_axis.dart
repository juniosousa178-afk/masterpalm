import 'package:flutter/material.dart';

/// Rótulo compacto do eixo Y. O tooltip do gráfico continua com o valor em reais.
const chartAxisLabelStyle = TextStyle(fontSize: 10, height: 1);

String compactChartAxisLabel(double value) {
  final negative = value < -0.5;
  final magnitude = value.abs();
  final String body;
  if (magnitude >= 1000000) {
    body = _scaled(magnitude / 1000000, ' mi');
  } else if (magnitude >= 1000) {
    body = _scaled(magnitude / 1000, ' mil');
  } else {
    body = magnitude.round().toString();
  }
  return negative ? '-$body' : body;
}

String _scaled(double scaled, String suffix) {
  final tenths = (scaled * 10).round() / 10;
  if ((tenths - tenths.round()).abs() < 0.001) {
    return '${tenths.round()}$suffix';
  }
  return '${tenths.toStringAsFixed(1).replaceAll('.', ',')}$suffix';
}

/// Largura do eixo a partir do texto do maior valor. Não usa uma largura fixa.
double chartYAxisReservedWidth(Iterable<double> values) {
  var peak = 0.0;
  for (final value in values) {
    final magnitude = value.abs();
    if (magnitude > peak) peak = magnitude;
  }
  final samples = <double>[0, peak, peak * 0.75, peak * 0.5, peak * 0.25];
  var widest = 0.0;
  for (final sample in samples) {
    final painter = TextPainter(
      text: TextSpan(
        text: compactChartAxisLabel(sample),
        style: chartAxisLabelStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest + 10;
}
