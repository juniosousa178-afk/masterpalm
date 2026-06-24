import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import 'plan_matrix.dart';
import '../services/planos_service.dart';

/// Resolve se o plano do usuário atual deve ser aplicado (admin da loja).
/// Programador e vendedor não são limitados por plano nesta camada.
abstract final class PlanAccessResolver {
  PlanAccessResolver._();

  static Future<bool> enforcePlanGateForCurrentUser() async {
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

  static Future<PlanAccessTier> currentTier() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return PlanAccessTier.freeLimited;
    }
    if (!await enforcePlanGateForCurrentUser()) {
      return PlanAccessTier.lifetime;
    }
    final email = (user.email ?? '').trim().toLowerCase();
    final access = await PlanosService().resolveEffectivePlanAccess(
      uid: user.uid,
      email: email,
    );
    if (access != null) {
      return access.effectiveTier;
    }
    return PlanAccessTier.freeLimited;
  }

  static Future<bool> allows(PlanGateFeature feature) async {
    if (!await enforcePlanGateForCurrentUser()) {
      return true;
    }
    final tier = await currentTier();
    return PlanMatrix.allows(tier, feature);
  }
}
