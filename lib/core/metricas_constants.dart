// Constantes únicas para critérios de métricas (painel, motor, relatórios).
// Ticket médio: semânticas por tela — ver comentários abaixo.

/// Dias sem venda para considerar produto "parado" (único critério global).
/// Unifica ex-insights (25) e motor (30).
const int kDiasProdutoParadoMetricas = 30;

/// Ticket médio no [MotorCrescimentoDetectorService]: média das vendas dos últimos
/// [kDiasProdutoParadoMetricas] dias (não é mês calendário).
///
/// Dashboard cards "Vendas hoje": apenas vendas do dia corrente.
///
/// Relatórios financeiros / gráficos: período escolhido pelo usuário (filtro de datas).
///
/// Análise IA: últimos 30 dias corridos (ver `analise_vendas_ia_screen.dart`).

/// Visitas do catálogo (`lojas/{lojaId}/config/stats` campo `visitas`): contagem **acumulada
/// lifetime**, não filtrada por período — não comparar diretamente com vendas do mês.
