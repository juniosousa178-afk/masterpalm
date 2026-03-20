// lib/models/dashboard_insight.dart
// Modelo leve para um insight exibido no painel (sem persistência Hive/Firestore).

/// Tipo de insight para estilo e ícone.
enum DashboardInsightType {
  produtoMaisVendido,
  produtoMaiorFaturamento,
  produtoParado,
  clienteDestaque,
  melhorVendedor,
  estoqueBaixo,
  metaProgresso,
  sugestaoPromocao,
}

/// Um insight gerado para o painel (mensagem amigável ao lojista).
class DashboardInsight {
  final DashboardInsightType type;
  final String message;
  final String? subtitle;
  final Map<String, dynamic>? data;

  const DashboardInsight({
    required this.type,
    required this.message,
    this.subtitle,
    this.data,
  });
}

/// Resultado consolidado do serviço de insights para a Home.
class DashboardInsightsResult {
  final List<DashboardInsight> insights;
  final double? metaAtual;
  final double? metaAtingida;

  const DashboardInsightsResult({
    required this.insights,
    this.metaAtual,
    this.metaAtingida,
  });
}
