import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../services/planos_service.dart';
import 'plan_return_link.dart';
import 'plan_return_screen.dart';

/// Loader real: usuário autenticado + acesso efetivo do servidor (`getMyPlanEffectiveAccess`).
/// Sem sessão, não consulta nada da conta.
PlanReturnStatusLoader productionPlanReturnLoader(
  Future<bool> Function() initFirebase,
) {
  return (PlanReturnRef ref) async {
    if (!await initFirebase()) {
      return const PlanReturnStatus(PlanReturnState.unavailable);
    }
    final auth = FirebaseAuth.instance;
    final user = await auth
        .authStateChanges()
        .first
        .timeout(const Duration(seconds: 8), onTimeout: () => auth.currentUser);
    if (user == null) {
      return const PlanReturnStatus(PlanReturnState.signedOut);
    }
    final svc = PlanosService();
    final access = await svc.fetchMyEffectivePlanAccess(forceRefresh: true);
    PlanInfo? plan;
    if (ref.kind == PlanReturnKind.planChange) {
      plan = await svc.fetchCurrentPlan(uid: user.uid, email: user.email ?? '');
    }
    return evaluatePlanReturn(ref: ref, access: access, plan: plan);
  };
}
