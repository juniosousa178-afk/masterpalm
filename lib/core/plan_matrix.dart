// Matriz central de acesso por plano (MasterPalm).
// Convive com IDs legados (free_trial_90d, mensal/anual) via PlanosService.normalizePlanId.

import '../services/planos_service.dart';

/// Nível efetivo de acesso (recursos / telas), após normalizar o plano.
enum PlanAccessTier {
  /// Após trial ou fallback.
  freeLimited,

  /// Básico mensal.
  basic,

  /// Intermediário mensal.
  intermediate,

  /// Pro mensal ou anual (ativo).
  pro,

  /// Trial 30d ou 90d ainda válido: mesmo conjunto de features que Pro.
  trialFull,

  /// Lifetime / root / override vitalício.
  lifetime,
}

/// Recursos usados para gates no menu e atalhos (não substitui permissões Hive).
enum PlanGateFeature {
  fornecedores,
  precificacao,
  pedidosPrePedidos,
  /// Hub combinado (telas agregadas).
  relatoriosFinanceirosHub,
  relatorioFinanceiroDetalhado,
  financeiroLancamentos,
  contasReceber,
  insights,
  maisVendidos,
  metasComissoes,
  vendedores,
  motorCrescimento,
  campanhasSugeridas,
  dicasIA,
  textosWhatsappIA,
  gerarPostagem,
  compartilharWhatsapp,
  analiseVendasIA,
  campanhasSorteios,
  globoSorteio,
  fretesCupons,
  canaisMeta,
  marketplaces,
  backupLoja,
  configurarPagamentosOnline,
  adminSync,
  relatorioRankingClientes,
  relatorioLucratividade,
  carrinhosAbandonados,

  /// Legado: rota de prévia usa subgates; [allows] retorna true para não travar a rota.
  lojaPreview,

  /// Moderação de avaliações do catálogo — Intermediário+.
  catalogoAvaliacoesModeracao,

  /// Notas fiscais — Intermediário+.
  notasFiscais,

  /// Importação por modelos — Intermediário+.
  modelosImportacao,
}

/// Modo de conteúdo do hub /relatorios (subgates internos).
enum PlanRelatoriosHubMode {
  minimal,
  basicSummary,
  operational,
  full,
}

/// Limites numéricos por tier (espelha regra comercial; LimitsGuard usa planId).
class PlanLimitsRow {
  final int maxProducts;
  final int maxClients;
  final int vendasMes;
  final int maxImagesPerProduct;
  final int maxBanners;
  final int maxMembers;

  const PlanLimitsRow({
    required this.maxProducts,
    required this.maxClients,
    required this.vendasMes,
    required this.maxImagesPerProduct,
    required this.maxBanners,
    required this.maxMembers,
  });
}

abstract final class PlanMatrix {
  PlanMatrix._();

  static PlanAccessTier tierFor(PlanInfo p) {
    if (p.planId == PlanId.lifetime) return PlanAccessTier.lifetime;

    if ((p.planId == PlanId.proMonthly || p.planId == PlanId.proYearly) &&
        p.isActive) {
      return PlanAccessTier.pro;
    }
    if (p.planId == PlanId.intermediateMonthly && p.isActive) {
      return PlanAccessTier.intermediate;
    }
    if (p.planId == PlanId.basicMonthly && p.isActive) {
      return PlanAccessTier.basic;
    }
    if ((p.planId == PlanId.freeTrial30d || p.planId == PlanId.freeTrial90d) &&
        p.isActive) {
      return PlanAccessTier.trialFull;
    }
    if (p.isFreeLimited) return PlanAccessTier.freeLimited;

    return PlanAccessTier.freeLimited;
  }

  /// Limites por plano canônico (Firestore). Trial pleno usa teto alto.
  static PlanLimitsRow limitsForPlanId(String? planId) {
    final p = PlanosService.normalizePlanId(planId);
    switch (p) {
      case PlanId.freeLimited:
        return const PlanLimitsRow(
          maxProducts: 30,
          maxClients: 20,
          vendasMes: 10,
          maxImagesPerProduct: 1,
          maxBanners: 1,
          maxMembers: 1,
        );
      case PlanId.basicMonthly:
        return const PlanLimitsRow(
          maxProducts: 300,
          maxClients: 500,
          vendasMes: 999999,
          maxImagesPerProduct: 5,
          maxBanners: 3,
          maxMembers: 1,
        );
      case PlanId.intermediateMonthly:
        return const PlanLimitsRow(
          maxProducts: 2000,
          maxClients: 3000,
          vendasMes: 999999,
          maxImagesPerProduct: 10,
          maxBanners: 10,
          maxMembers: 3,
        );
      case PlanId.freeTrial30d:
      case PlanId.freeTrial90d:
        return const PlanLimitsRow(
          maxProducts: 999999,
          maxClients: 999999,
          vendasMes: 999999,
          maxImagesPerProduct: 10,
          maxBanners: 10,
          maxMembers: 10,
        );
      case PlanId.proMonthly:
      case PlanId.proYearly:
      case PlanId.lifetime:
        return const PlanLimitsRow(
          maxProducts: 999999,
          maxClients: 999999,
          vendasMes: 999999,
          maxImagesPerProduct: 10,
          maxBanners: 10,
          maxMembers: 50,
        );
      default:
        return limitsForPlanId(PlanId.freeLimited);
    }
  }

  static Map<String, int> limitsMapForPlanId(String? planId) {
    final r = limitsForPlanId(planId);
    return {
      'maxProducts': r.maxProducts,
      'maxClients': r.maxClients,
      'vendasMes': r.vendasMes,
      'maxImagesPerProduct': r.maxImagesPerProduct,
      'maxBanners': r.maxBanners,
      'maxMembers': r.maxMembers,
      'maxOrdersPerDay': 999,
    };
  }

  /// Conteúdo permitido dentro de /relatorios (rota sempre aberta).
  static PlanRelatoriosHubMode relatoriosHubMode(PlanAccessTier tier) {
    switch (tier) {
      case PlanAccessTier.freeLimited:
        return PlanRelatoriosHubMode.minimal;
      case PlanAccessTier.basic:
        return PlanRelatoriosHubMode.basicSummary;
      case PlanAccessTier.intermediate:
        return PlanRelatoriosHubMode.operational;
      case PlanAccessTier.pro:
      case PlanAccessTier.trialFull:
      case PlanAccessTier.lifetime:
        return PlanRelatoriosHubMode.full;
    }
  }

  static bool allows(PlanAccessTier tier, PlanGateFeature f) {
    if (tier == PlanAccessTier.lifetime || tier == PlanAccessTier.trialFull) {
      return true;
    }
    if (tier == PlanAccessTier.pro) return true;

    /// Pré-visualização do catálogo: rota sem gate; restrições no [PublicCatalogScreen].
    if (f == PlanGateFeature.lojaPreview) return true;

    if (tier == PlanAccessTier.intermediate) {
      return !_isProOnly(f);
    }

    if (tier == PlanAccessTier.basic) {
      if (_isProOnly(f)) return false;
      return !_isIntermediateOnly(f);
    }

    // freeLimited: somente o que o produto liberou explicitamente (rotas sem gate usam subgates).
    return _allowsFreeLimited(f);
  }

  static bool _allowsFreeLimited(PlanGateFeature f) {
    return false;
  }

  static bool _isProOnly(PlanGateFeature f) {
    switch (f) {
      case PlanGateFeature.metasComissoes:
      case PlanGateFeature.vendedores:
      case PlanGateFeature.motorCrescimento:
      case PlanGateFeature.campanhasSugeridas:
      case PlanGateFeature.dicasIA:
      case PlanGateFeature.textosWhatsappIA:
      case PlanGateFeature.gerarPostagem:
      case PlanGateFeature.compartilharWhatsapp:
      case PlanGateFeature.analiseVendasIA:
      case PlanGateFeature.campanhasSorteios:
      case PlanGateFeature.globoSorteio:
      case PlanGateFeature.fretesCupons:
      case PlanGateFeature.canaisMeta:
      case PlanGateFeature.marketplaces:
      case PlanGateFeature.adminSync:
        return true;
      default:
        return false;
    }
  }

  static bool _isIntermediateOnly(PlanGateFeature f) {
    switch (f) {
      case PlanGateFeature.fornecedores:
      case PlanGateFeature.precificacao:
      case PlanGateFeature.pedidosPrePedidos:
      case PlanGateFeature.relatorioFinanceiroDetalhado:
      case PlanGateFeature.financeiroLancamentos:
      case PlanGateFeature.insights:
      case PlanGateFeature.configurarPagamentosOnline:
      case PlanGateFeature.relatorioRankingClientes:
      case PlanGateFeature.relatorioLucratividade:
      case PlanGateFeature.carrinhosAbandonados:
      case PlanGateFeature.catalogoAvaliacoesModeracao:
      case PlanGateFeature.notasFiscais:
      case PlanGateFeature.maisVendidos:
      case PlanGateFeature.relatoriosFinanceirosHub:
      case PlanGateFeature.modelosImportacao:
        return true;
      default:
        return false;
    }
  }

  static String upgradeHint(PlanGateFeature f) {
    switch (f) {
      case PlanGateFeature.fornecedores:
      case PlanGateFeature.precificacao:
      case PlanGateFeature.pedidosPrePedidos:
        return 'Disponível a partir do plano Intermediário: compras, precificação e pedidos.';
      case PlanGateFeature.relatorioFinanceiroDetalhado:
      case PlanGateFeature.financeiroLancamentos:
      case PlanGateFeature.insights:
      case PlanGateFeature.configurarPagamentosOnline:
        return 'Faça upgrade para o Intermediário e ganhe relatórios e operações completas.';
      case PlanGateFeature.relatorioRankingClientes:
      case PlanGateFeature.relatorioLucratividade:
      case PlanGateFeature.carrinhosAbandonados:
        return 'Ranking, lucratividade e carrinhos abandonados fazem parte do Intermediário ou Pro.';
      case PlanGateFeature.fretesCupons:
        return 'Fretes e cupons estão no plano Pro.';
      case PlanGateFeature.contasReceber:
        return 'Contas a receber fazem parte do plano Básico ou superior.';
      case PlanGateFeature.relatoriosFinanceirosHub:
      case PlanGateFeature.maisVendidos:
      case PlanGateFeature.backupLoja:
      case PlanGateFeature.adminSync:
        return 'Organize sua loja com o plano Básico ou superior.';
      case PlanGateFeature.lojaPreview:
        return 'Na prévia, free e básico simulam catálogo com pedido pelo WhatsApp; checkout completo no Intermediário.';
      case PlanGateFeature.catalogoAvaliacoesModeracao:
        return 'Moderação de avaliações do catálogo faz parte do Intermediário ou Pro.';
      case PlanGateFeature.notasFiscais:
        return 'Notas fiscais integradas ao fluxo exigem plano Intermediário ou superior.';
      case PlanGateFeature.modelosImportacao:
        return 'Importação por modelos de planilha está no plano Intermediário ou superior.';
      default:
        return 'Desbloqueie no plano Pro: equipe, IA, campanhas e integrações.';
    }
  }
}
