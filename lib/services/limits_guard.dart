import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/logger.dart';

import 'firestore_paths.dart';
import 'planos_service.dart';
import 'subscription_service.dart';

/// Guarda de limites por plano.
/// Integrado com PlanosService: free_limited (após trial) e freelight têm restrições.
class LimitsGuard {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------- Helpers ----------

  /// Planos com limites aplicados (trial, free limitado, paid com teto de imagens/banners)
  static const _limitedPlans = [
    'free_trial_90d',
    'free_limited',
    'freelight',
    'pro_monthly',
    'pro_yearly',
    'lifetime',
  ];

  /// Verifica se o plano tem restrições de limite
  bool hasLimits(String? planId) {
    final p = (planId ?? '').toLowerCase().trim();
    return _limitedPlans.contains(p);
  }

  static Map<String, int> _limitsForPlan(String? planId) {
    final p = (planId ?? '').toLowerCase().trim();
    if (p == PlanId.freeTrial90d) return SubscriptionService.trialLimits;
    if (p == PlanId.freeLimited || p == 'freelight') return SubscriptionService.freeLimitedLimits;
    if (p == PlanId.proMonthly || p == PlanId.proYearly || p == PlanId.lifetime) {
      return SubscriptionService.paidLimits;
    }
    return SubscriptionService.freeLimits;
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

  /// Obtém o planId do usuário atual (users/{uid}.currentPlanId ou PlanosService)
  Future<String?> _currentPlanId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final plan = await PlanosService().fetchCurrentPlan(
        uid: user.uid,
        email: (user.email ?? '').trim().toLowerCase(),
      );
      return plan?.planId;
    } catch (_) {
      return null;
    }
  }

  // ---------- Regras ----------

  /// Verifica se pode adicionar produto.
  /// Se [planId] for null, busca do usuário atual.
  Future<bool> canAddProduto(
    String lojaId, {
    String? planId,
  }) async {
    try {
      final p = planId ?? await _currentPlanId();
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
      final p = planId ?? await _currentPlanId();
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
    final p = planId ?? await _currentPlanId();
    if (!hasLimits(p)) return 999;
    return _limitFor(p, 'maxImagesPerProduct');
  }

  /// Limite máximo de banners (desktop + mobile) para o plano
  Future<int> maxBanners(String? planId) async {
    final p = planId ?? await _currentPlanId();
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
      final p = planId ?? await _currentPlanId();
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
      final p = planId ?? await _currentPlanId();
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

  /// Verifica se pode adicionar venda neste mês.
  Future<bool> canAddVenda(
    String lojaId, {
    String? planId,
  }) async {
    try {
      final p = planId ?? await _currentPlanId();
      if (!hasLimits(p)) return true;

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

      return totalMes < _limitFor(p, 'vendasMes');
    } catch (e, st) {
      logE('[LimitsGuard] canAddVenda erro (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  // ---------- Retrocompatibilidade (userStatus) ----------

  String _planOf(Map<String, dynamic>? userStatus) {
    final plan = userStatus?['plan'] ?? userStatus?['currentPlanId'];
    return (plan as String?)?.toLowerCase().trim() ?? 'freelight';
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
