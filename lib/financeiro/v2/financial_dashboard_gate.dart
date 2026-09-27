/// Fase 2A. A prévia não substitui `/financeiro` e não entra no menu.
abstract final class FinancialV2DashboardGate {
  static const previewRoute = '/financeiro_v2_preview';

  static const bool replacesCurrentFinanceiro = false;
  static const bool showInHomeMenu = false;

  static bool previewAllowed(bool isAdmin) => isAdmin;
}
