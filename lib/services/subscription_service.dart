// lib/services/subscription_service.dart
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/role_utils.dart';
import 'planos_service.dart';

class SubscriptionStatus {
  final String plan;          // e.g. 'freelight', 'pro', ...
  final bool active;          // se o plano está ativo
  final DateTime? expiresAt;  // validade, se houver
  final Map<String, int> limits;

  const SubscriptionStatus({
    required this.plan,
    required this.active,
    required this.limits,
    this.expiresAt,
  });

  SubscriptionStatus copyWith({
    String? plan,
    bool? active,
    DateTime? expiresAt,
    Map<String, int>? limits,
  }) {
    return SubscriptionStatus(
      plan: plan ?? this.plan,
      active: active ?? this.active,
      expiresAt: expiresAt ?? this.expiresAt,
      limits: limits ?? this.limits,
    );
  }

  static SubscriptionStatus free() => const SubscriptionStatus(
        plan: 'freelight',
        active: true,
        limits: SubscriptionService.freeLimits,
        expiresAt: null,
      );

  /// Aceita vários formatos de doc e nunca dá crash por cast errado.
  static SubscriptionStatus fromData(Map<String, dynamic> data) {
    String normalizePlan(String? raw) {
      final n = PlanosService.normalizePlanId(raw);
      return n.isEmpty ? 'freelight' : n;
    }

    // ---------- PLAN ----------
    dynamic rawPlan = data['currentPlanId'] ?? data['planId'];

    // se vier aninhado, tipo { plan: { id: 'freelight', ... } }
    if (rawPlan is Map<String, dynamic>) {
      rawPlan = rawPlan['id'] ?? rawPlan['planId'] ?? rawPlan['name'];
    }

    // fallback: alguns sistemas gravam planId na raiz
    rawPlan ??= data['planId'];

    String plan = rawPlan is String ? normalizePlan(rawPlan) : 'freelight';

    // ---------- ACTIVE ----------
    dynamic rawActive = data['active'];
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final trialing = data['trialing'] == true;

    // se estiver dentro de um map de status, tenta extrair
    if (rawActive is Map<String, dynamic>) {
      final statusStr = rawActive['status'];
      if (statusStr is String) {
        rawActive = statusStr.toLowerCase() == 'active';
      }
    }

    bool active;
    if (rawActive is bool) {
      active = rawActive;
    } else {
      if (status.isNotEmpty) {
        active = status == 'active' || status == 'trialing' || status == 'pending';
      } else {
        // fallback legado
        active = plan != 'freelight';
      }
    }

    // ---------- EXPIRES ----------
    dynamic rawExpires = data['currentPeriodEnd'] ?? data['expiresAt'];

    // se vir dentro de plan como map
    // Sem fallback em users.plan.*; currentPeriodEnd é a fonte principal.

    final expiresAt = _tsToDate(rawExpires);

    // ---------- LIMITS ----------
    final Map<String, int> limits = {};
    dynamic rawLimits = data['limits'];

    // Sem fallback em users.plan.limits; limites vêm do plano canônico.

    if (rawLimits is Map) {
      rawLimits.forEach((k, v) {
        if (k is String && v is num) {
          limits[k] = v.toInt();
        }
      });
    }

    // Fallback: mescla com os limites do FREE para evitar null na UI
    final merged = {...SubscriptionService.freeLimits, ...limits};

    if (trialing && plan == 'freelight') {
      plan = 'free_trial_90d';
    }

    return SubscriptionStatus(
      plan: plan,
      active: active,
      expiresAt: expiresAt,
      limits: merged,
    );
  }

  static DateTime? _tsToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
    }
    return null;
  }
}

class SubscriptionService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Limites do trial (free_trial_90d – 3 meses)
  static const Map<String, int> trialLimits = {
    'maxProducts': 80,
    'maxClients': 150,
    'vendasMes': 50,
    'maxImagesPerProduct': 10,
    'maxBanners': 10,
    'maxMembers': 3,
    'maxOrdersPerDay': 50,
  };

  /// Limites do plano pago (pro_monthly, pro_yearly, lifetime): 10 fotos/produto, 10 banners
  static const Map<String, int> paidLimits = {
    'maxProducts': 999999,
    'maxClients': 999999,
    'vendasMes': 999999,
    'maxImagesPerProduct': 10,
    'maxBanners': 10,
    'maxMembers': 10,
    'maxOrdersPerDay': 999,
  };

  /// Limites do plano free genérico (freelight – fallback)
  static const Map<String, int> freeLimits = {
    'maxProducts': 200,
    'maxImagesPerProduct': 6,
    'maxBanners': 6,
    'maxMembers': 3,
    'maxOrdersPerDay': 50,
    'maxClients': 500,
    'vendasMes': 500,
  };

  /// Limites do plano free_limited (após trial expirado – Opção B)
  static const Map<String, int> freeLimitedLimits = {
    'maxProducts': 30,
    'maxImagesPerProduct': 1,
    'maxBanners': 1,
    'maxMembers': 1,
    'maxOrdersPerDay': 20,
    'maxClients': 20,
    'vendasMes': 10,
  };

  /// UID root legado (atalho) — e-mail root: [RoleUtils.isRootEmail].
  static const String rootUid = 'vd0X6xXlq4be0cKhmIOiDtXTvKb2';

  /// Preferir [RoleUtils.isRootEmail] — lista canônica em `lib/utils/role_utils.dart`.
  static const String rootEmail = 'masterpalm26@gmail.com';

  static bool get isSignedIn => _auth.currentUser != null;

  static bool get isRoot {
    final u = _auth.currentUser;
    if (u == null) return false;
    return (u.uid == rootUid) || RoleUtils.isRootEmail(u.email);
  }

  /// Lê users/{uid} (sem query). Caso não exista ou negado -> retorna FREE.
  static Future<SubscriptionStatus> getStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      dev.log('[SUBS] sem usuário -> FREE');
      return SubscriptionStatus.free();
    }

    try {
      final doc = await _db.doc('users/${user.uid}').get();
      if (!doc.exists) {
        dev.log('[SUBS] users/${user.uid} inexistente -> FREE');
        return SubscriptionStatus.free();
      }

      final Map<String, dynamic> data = (doc.data() ?? <String, dynamic>{});
      final status = SubscriptionStatus.fromData(data);

      dev.log('[SUBS] ok plan=${status.plan} active=${status.active}');
      return status;
    } on FirebaseException catch (e) {
      // Alinhado às rules: se faltar permissão, não trava o app
      if (e.code == 'permission-denied') {
        dev.log('[SUBS] permission-denied em users/${user.uid} -> FREE');
        return SubscriptionStatus.free();
      }
      rethrow;
    }
  }

  /// Stream do doc do próprio usuário. Cai em FREE se faltar permissão.
  static Stream<SubscriptionStatus> watchStatus() async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield SubscriptionStatus.free();
      return;
    }
    try {
      yield* _db.doc('users/${user.uid}').snapshots().map((snap) {
        if (!snap.exists) return SubscriptionStatus.free();
        final Map<String, dynamic> data = (snap.data() ?? <String, dynamic>{});
        return SubscriptionStatus.fromData(data);
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        yield SubscriptionStatus.free();
        return;
      }
      rethrow;
    }
  }

  /// Bootstrap: cria /lojas/{lojaId}/members/{uid} se não existir (self-create)
  /// Compatível com as rules (o próprio usuário pode criar o primeiro doc).
  static Future<void> ensureMember(String lojaId, {String role = 'admin'}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _db.doc('lojas/$lojaId/members/${user.uid}');
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'uid': user.uid,
          'email': user.email,
          'role': isRoot ? 'owner' : role, // root vira owner por conveniência
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        dev.log('[SUBS] members bootstrap criado para loja=$lojaId uid=${user.uid}');
      }
    } on FirebaseException catch (e) {
      // se negar, apenas loga – sua UI não deve quebrar por isso
      dev.log('[SUBS] ensureMember falhou (${e.code}) loja=$lojaId uid=${user.uid}');
    }
  }
}