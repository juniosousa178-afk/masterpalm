import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import 'access_scope_service.dart';
import 'plan_matrix.dart';
import '../services/planos_service.dart';

/// Resolve o plano da LOJA para gates de feature.
///
/// M3.8 MULTI-R2: o plano pertence exclusivamente à loja.
/// - Nunca consultar plano individual do vendedor.
/// - Nunca gravar/ler plano em vendedores/{uid} nem plano-por-e-mail de vendedor.
/// - Vendedor/programador: herdam acesso operacional da loja (não passam pelo gate).
/// - Admin: plano efetivo da conta da loja (dono/admin).
abstract final class PlanAccessResolver {
  PlanAccessResolver._();

  static Future<bool> enforcePlanGateForCurrentUser() async {
    assert(AccessScopeService.planBelongsToStoreOnly());
    assert(!AccessScopeService.sellerRequiresIndividualPlan());
    try {
      if (!Hive.isBoxOpen('sessao')) {
        await Hive.openBox('sessao');
      }
      final tipo =
          Hive.box('sessao').get('tipo_usuario')?.toString().trim().toLowerCase() ??
              '';
      if (tipo == 'programador' || tipo == 'vendedor') {
        return false;
      }
    } catch (_) {}
    return true;
  }

  static Future<PlanGateSnapshot> currentSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PlanGateSnapshot(
        tier: PlanAccessTier.freeLimited,
        accountStatus: 'blocked',
      );
    }
    if (!await enforcePlanGateForCurrentUser()) {
      return const PlanGateSnapshot(tier: PlanAccessTier.lifetime);
    }
    final email = (user.email ?? '').trim().toLowerCase();
    final access = await PlanosService().resolveEffectivePlanAccess(
      uid: user.uid,
      email: email,
    );
    if (access == null) {
      return const PlanGateSnapshot(tier: PlanAccessTier.freeLimited);
    }
    return PlanGateSnapshot(
      tier: access.effectiveTier,
      accountStatus: access.effectiveStatus,
    );
  }

  static Future<PlanAccessTier> currentTier() async {
    return (await currentSnapshot()).tier;
  }

  static Future<bool> allows(PlanGateFeature feature) async {
    if (!await enforcePlanGateForCurrentUser()) {
      return true;
    }
    final snap = await currentSnapshot();
    return PlanMatrix.allows(
      snap.tier,
      feature,
      accountStatus: snap.accountStatus,
    );
  }
}

class PlanGateSnapshot {
  const PlanGateSnapshot({
    required this.tier,
    this.accountStatus,
  });

  final PlanAccessTier tier;
  final String? accountStatus;
}
