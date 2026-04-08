// lib/services/license_manager.dart
//
// ✅ Compatível com o modelo novo (assinaturas em Firestore) e o legado (deviceId + código)
// ✅ Consulta espelho em users/{uid}, subscriptions e fallback Hive + código legado
// ✅ Sem warnings de null-safety

import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// -------- PLANOS E LIMITES --------
class PlanId {
  static const String freeTrial  = 'free_trial';
  static const String proMonthly = 'pro_monthly';
  static const String proYearly  = 'pro_yearly';
}

class PlanLimits {
  final int maxProdutos;
  final int maxClientes;
  final bool suportePrioritario;
  final bool dominioProprio;

  const PlanLimits({
    required this.maxProdutos,
    required this.maxClientes,
    this.suportePrioritario = false,
    this.dominioProprio = false,
  });
}

const Map<String, PlanLimits> kLimitsByPlan = {
  PlanId.freeTrial: PlanLimits(
    maxProdutos: 10,
    maxClientes: 50,
  ),
  PlanId.proMonthly: PlanLimits(
    maxProdutos: 999999,
    maxClientes: 999999,
  ),
  PlanId.proYearly: PlanLimits(
    maxProdutos: 999999,
    maxClientes: 999999,
    suportePrioritario: true,
    dominioProprio: true,
  ),
};

/// -------- GERENCIADOR DE LICENÇA --------
class LicenseManager {
  static String _normalizePlanId(String? raw) {
    final p = (raw ?? '').trim().toLowerCase();
    switch (p) {
      case 'mensal':
      case 'pro_monthly':
        return PlanId.proMonthly;
      case 'anual':
      case 'pro_yearly':
        return PlanId.proYearly;
      case 'trial_90d':
      case 'free_trial_90d':
      case 'free_trial':
        return 'free_trial_90d';
      case 'free_limited':
        return 'free_limited';
      default:
        return p;
    }
  }

  // ========== DEVICE ID ==========
  static Future<String> getDeviceId() async {
    final di = DeviceInfoPlugin();

    // Android
    try {
      final a = await di.androidInfo;
      return a.id.isNotEmpty ? a.id : 'android-${a.model}';
    } catch (_) {}

    // iOS
    try {
      final i = await di.iosInfo;
      final idfa = i.identifierForVendor;
      if (idfa != null && idfa.isNotEmpty) return idfa;
      return 'ios-${i.name}';
    } catch (_) {}

    // Web
    try {
      final w = await di.webBrowserInfo;
      return '${w.vendor ?? 'web'}-${w.userAgent ?? 'ua'}';
    } catch (_) {}

    return 'unknown';
  }

  static bool isLicenseValid(String deviceId, String codigo) {
    final expected = base64Url.encode(utf8.encode('$deviceId#MASTERPALM'));
    return codigo.trim() == expected;
  }

  // ========== CACHE LOCAL ==========
  static Future<void> cachePlanLocally({
    required String planId,
    required DateTime? expiresAt,
  }) async {
    final normalized = _normalizePlanId(planId);
    final box = await Hive.openBox('licenca');
    await box.put('currentPlanId', normalized);
    if (expiresAt != null) {
      await box.put('expiresAt', expiresAt.toIso8601String());
    }
    await box.put('ativado', true);
    try {
      final sessao = await Hive.openBox('sessao');
      await sessao.put('plan_plan_id', normalized);
      await sessao.put('plan_expired', expiresAt != null && expiresAt.isBefore(DateTime.now()));
      await sessao.put('plan_cache_until', DateTime.now().millisecondsSinceEpoch + 3600000);
    } catch (_) {}
  }

  static Future<String?> getCachedPlanId() async {
    final box = await Hive.openBox('licenca');
    return (box.get('currentPlanId') as String?)?.trim();
  }

  static Future<DateTime?> getCachedExpiry() async {
    final box = await Hive.openBox('licenca');
    final raw = box.get('expiresAt');
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  // ========== HELPERS ==========
  static DateTime? _parseEnd(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static bool _isActiveStatus(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    return s == 'active' || s == 'trialing';
  }

  static bool _notExpired(DateTime? end) =>
      end == null || end.isAfter(DateTime.now());

  // ========== FIRESTORE CHECKS ==========
  static Future<bool> _checkMirrorUserDoc(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists) return false;

    final d = doc.data() ?? <String, dynamic>{};

    String planId = _normalizePlanId(
      (d['currentPlanId'] ?? d['current_plan_id'])?.toString(),
    );
    String status = (d['status'] ?? 'active').toString();
    if (status.isEmpty) status = 'active';
    final end =
        _parseEnd(d['current_period_end'] ?? d['currentPeriodEnd']);

    if (planId.isNotEmpty && _isActiveStatus(status) && _notExpired(end)) {
      await cachePlanLocally(planId: planId, expiresAt: end);
      return true;
    }
    return false;
  }

  static Future<bool> _checkSubscriptions(User user) async {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('subscriptions');

    try {
      final snap = await col
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      for (final doc in snap.docs) {
        final s = doc.data();
        final planId = _normalizePlanId(
          (s['plan_id'] ?? s['planId'] ?? '').toString(),
        );
        final status = (s['status'] as String?) ?? 'active';
        final end =
            _parseEnd(s['current_period_end'] ?? s['currentPeriodEnd']);

        if (planId.isNotEmpty &&
            _isActiveStatus(status) &&
            _notExpired(end)) {
          await cachePlanLocally(planId: planId, expiresAt: end);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // ========== VERIFICAÇÃO PRINCIPAL ==========
  static Future<bool> hasValidAccessFallbackLegacy() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // 0) Root / programador – mesmo critério do PlanosService (lifetime automático)
    const rootEmails = {'masterpalm26@gmail.com', 'masterpalm@gmail.com', 'admin@masterpalm.com'};
    if (user.email != null && rootEmails.contains(user.email!.toLowerCase().trim())) {
      return true;
    }

    // 1) espelho em users/{uid}
    if (await _checkMirrorUserDoc(user)) return true;

    // 2) coleção de subscriptions (somente leitura Firestore; escrita via backend)
    if (await _checkSubscriptions(user)) return true;

    // 3) Não liberar premium só por Hive — evita APK modificado / cache adulterado.

    // 4) DEPRECATED: `licenca.codigo` aposentado para liberação funcional.
    // Mantido apenas para leitura passiva/compatibilidade de dados antigos.
    try {
      final box = await Hive.openBox('licenca');
      box.get('codigo');
    } catch (_) {}

    return false;
  }

  static Future<PlanLimits> currentPlanLimits() async {
    final planId = await getCachedPlanId() ?? PlanId.freeTrial;
    return kLimitsByPlan[planId] ?? kLimitsByPlan[PlanId.freeTrial]!;
  }
}
