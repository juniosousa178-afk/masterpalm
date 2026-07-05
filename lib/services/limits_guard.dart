import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../core/master_plan_admin_messages.dart';
import '../core/plan_matrix.dart';

import 'firestore_paths.dart';
import 'planos_service.dart';

/// Resultado explícito da checagem de limite mensal de vendas.
enum VendaLimitStatus {
  allowed,
  blockedAtLimit,
  checkFailed,
}

class VendaLimitCheckResult {
  const VendaLimitCheckResult({
    required this.status,
    this.planId,
    this.vendasNoMes,
    this.limiteMensal,
  });

  final VendaLimitStatus status;
  final String? planId;
  final int? vendasNoMes;
  final int? limiteMensal;

  bool get canAdd => status == VendaLimitStatus.allowed;

  String userMessage() {
    switch (status) {
      case VendaLimitStatus.allowed:
        return '';
      case VendaLimitStatus.blockedAtLimit:
        final planLabel = masterPlanIdLabel(planId);
        final limite = limiteMensal ?? 0;
        return 'Limite de vendas do mês atingido no plano $planLabel '
            '($limite/mês). Faça upgrade para registrar mais vendas.';
      case VendaLimitStatus.checkFailed:
        return 'Não foi possível verificar o limite de vendas do plano. '
            'Verifique a conexão e tente novamente em instantes.';
    }
  }
}

/// Guarda de limites por plano.
/// Integrado com PlanosService: free_limited (após trial) e freelight têm restrições.
class LimitsGuard {
  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static Future<String?> Function()? debugEffectivePlanIdOverride;

  FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  // ---------- Helpers ----------

  /// IDs canônicos reconhecidos para gate de vendas/mês (inclui legado freelight).
  static const _canonicalPlanIds = {
    PlanId.freeTrial30d,
    PlanId.freeTrial90d,
    PlanId.freeLimited,
    'freelight',
    PlanId.basicMonthly,
    PlanId.intermediateMonthly,
    PlanId.proMonthly,
    PlanId.proYearly,
    PlanId.lifetime,
  };

  static bool _isCanonicalPlanId(String? planId) {
    final p = PlanosService.normalizePlanId(planId);
    return _canonicalPlanIds.contains(p);
  }

  /// Planos com limites aplicados (trial, free limitado, paid com teto de imagens/banners)
  static const _limitedPlans = [
    'free_trial_30d',
    'free_trial_90d',
    'free_limited',
    'freelight',
    'basic_monthly',
    'intermediate_monthly',
    'pro_monthly',
    'pro_yearly',
    'lifetime',
  ];

  /// Verifica se o plano tem restrições de limite
  bool hasLimits(String? planId) {
    final raw = (planId ?? '').trim();
    if (raw.isEmpty) return false;
    final p = PlanosService.normalizePlanId(planId);
    return _limitedPlans.contains(p);
  }

  static Map<String, int> _limitsForPlan(String? planId) {
    final p = PlanosService.normalizePlanId(planId);
    return PlanMatrix.limitsMapForPlanId(p);
  }

  /// Lê o limite configurado conforme o plano
  int _limitFor(String? planId, String key) {
    final limits = _limitsForPlan(planId);
    return limits[key] ?? 0;
  }

  /// Retorna a contagem (Aggregate Query) de uma coleção/consulta
  Future<int> _countOf(Query<Map<String, dynamic>> query) async {
    final snap = await query.count().get();
    return snap.count ?? 0;
  }

  /// Obtém o planId efetivo do usuário (gates e limites — cortesia incluída).
  Future<String?> _effectivePlanIdForLimits() async {
    if (debugEffectivePlanIdOverride != null) {
      return debugEffectivePlanIdOverride!();
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      return await PlanosService().effectivePlanIdForGates(
        uid: user.uid,
        email: (user.email ?? '').trim().toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolvePlanIdForVendaLimit({String? planId}) async {
    if (planId != null) {
      final raw = planId.trim();
      if (raw.isEmpty) return null;
      return PlanosService.normalizePlanId(raw);
    }
    final efetivo = await _effectivePlanIdForLimits();
    if (efetivo == null || efetivo.trim().isEmpty) return null;
    return PlanosService.normalizePlanId(efetivo);
  }

  // ---------- Regras ----------

  /// Verifica se pode adicionar produto.
  /// Se [planId] for null, busca do usuário atual.
  Future<bool> canAddProduto(
    String lojaId, {
    String? planId,
  }) async {
    try {
      final p = planId ?? await _effectivePlanIdForLimits();
      if (!hasLimits(p)) return true;

      final total = await _countOf(
        _db.collection('lojas').doc(lojaId).collection(FSPaths.estoqueProdutosCol),
      );
      return total < _limitFor(p, 'maxProducts');
    } catch (e, st) {
      logE('[LimitsGuard] canAddProduto erro (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Verifica se pode adicionar mais imagens ao produto.
  /// [currentCount] = quantidade atual de imagens do produto.
  Future<bool> canAddImagemProduto(
    String lojaId, {
    String? planId,
    required int currentCount,
  }) async {
    try {
      final p = planId ?? await _effectivePlanIdForLimits();
      if (!hasLimits(p)) return true;
      final max = _limitFor(p, 'maxImagesPerProduct');
      return currentCount < max;
    } catch (e, st) {
      logE('[LimitsGuard] canAddImagemProduto erro (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Limite máximo de imagens por produto para o plano
  Future<int> maxImagesPerProduct(String? planId) async {
    final p = planId ?? await _effectivePlanIdForLimits();
    if (!hasLimits(p)) return 999;
    return _limitFor(p, 'maxImagesPerProduct');
  }

  /// Limite máximo de banners (desktop + mobile) para o plano
  Future<int> maxBanners(String? planId) async {
    final p = planId ?? await _effectivePlanIdForLimits();
    if (!hasLimits(p)) return 99;
    return _limitFor(p, 'maxBanners');
  }

  /// Verifica se pode adicionar mais banners (total desktop + mobile)
  Future<bool> canAddBanner(
    String lojaId, {
    String? planId,
    required int currentTotalBanners,
  }) async {
    try {
      final p = planId ?? await _effectivePlanIdForLimits();
      if (!hasLimits(p)) return true;
      final max = _limitFor(p, 'maxBanners');
      return currentTotalBanners < max;
    } catch (e, st) {
      logE('[LimitsGuard] canAddBanner erro (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Verifica se pode adicionar cliente.
  Future<bool> canAddCliente(
    String lojaId, {
    String? planId,
  }) async {
    try {
      final p = planId ?? await _effectivePlanIdForLimits();
      if (!hasLimits(p)) return true;

      final total = await _countOf(
        _db.collection('lojas').doc(lojaId).collection(FSPaths.estoqueClientesCol),
      );
      return total < _limitFor(p, 'maxClients');
    } catch (e, st) {
      logE('[LimitsGuard] canAddCliente erro (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Checagem detalhada — distingue limite real de falha de consulta/plano.
  Future<VendaLimitCheckResult> checkVendaLimit(
    String lojaId, {
    String? planId,
  }) async {
    try {
      final p = await _resolvePlanIdForVendaLimit(planId: planId);
      if (p == null || !_isCanonicalPlanId(p)) {
        return const VendaLimitCheckResult(status: VendaLimitStatus.checkFailed);
      }
      if (!hasLimits(p)) {
        return const VendaLimitCheckResult(status: VendaLimitStatus.allowed);
      }

      final limite = _limitFor(p, 'vendasMes');
      final now = DateTime.now();
      final first = DateTime(now.year, now.month, 1);
      final lastExclusive = DateTime(now.year, now.month + 1, 1);

      final totalMes = await _countOf(
        _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueVendasCol)
            .where('createdAt', isGreaterThanOrEqualTo: first)
            .where('createdAt', isLessThan: lastExclusive),
      );

      if (totalMes < limite) {
        return VendaLimitCheckResult(
          status: VendaLimitStatus.allowed,
          planId: p,
          vendasNoMes: totalMes,
          limiteMensal: limite,
        );
      }

      return VendaLimitCheckResult(
        status: VendaLimitStatus.blockedAtLimit,
        planId: p,
        vendasNoMes: totalMes,
        limiteMensal: limite,
      );
    } catch (e, st) {
      logE('[LimitsGuard] checkVendaLimit erro (type=${e.runtimeType})', error: e, st: st);
      return const VendaLimitCheckResult(status: VendaLimitStatus.checkFailed);
    }
  }

  /// Verifica se pode adicionar venda neste mês.
  Future<bool> canAddVenda(
    String lojaId, {
    String? planId,
  }) async {
    final result = await checkVendaLimit(lojaId, planId: planId);
    return result.canAdd;
  }

  // ---------- Retrocompatibilidade (userStatus) ----------

  String _planOf(Map<String, dynamic>? userStatus) {
    final plan = userStatus?['currentPlanId'];
    final n = PlanosService.normalizePlanId(plan?.toString());
    if (n.isNotEmpty) return n;
    return PlanId.freeLimited;
  }

  /// @deprecated Use canAddProduto(lojaId, planId: ...) com planId de PlanosService
  Future<bool> canAddProdutoLegacy(
    String lojaId,
    Map<String, dynamic>? userStatus,
  ) async {
    return canAddProduto(lojaId, planId: _planOf(userStatus));
  }

  /// @deprecated Use canAddCliente(lojaId, planId: ...)
  Future<bool> canAddClienteLegacy(
    String lojaId,
    Map<String, dynamic>? userStatus,
  ) async {
    return canAddCliente(lojaId, planId: _planOf(userStatus));
  }

  /// @deprecated Use canAddVenda(lojaId, planId: ...)
  Future<bool> canAddVendaLegacy(
    String lojaId,
    Map<String, dynamic>? userStatus,
  ) async {
    return canAddVenda(lojaId, planId: _planOf(userStatus));
  }
}
