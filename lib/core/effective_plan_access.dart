import 'master_plan_access_models.dart';
import 'plan_matrix.dart';
import '../services/planos_service.dart';

/// Estado central de acesso efetivo — gates e limites usam [effectivePlanId].
class EffectivePlanAccess {
  final String contractedPlanId;
  final String effectivePlanId;
  final String accessSource;
  final String? effectiveStatus;
  final DateTime? currentPeriodEnd;
  final MasterPlanCourtesySummary courtesy;
  final MasterPlanRenewalSummary renewal;

  const EffectivePlanAccess({
    required this.contractedPlanId,
    required this.effectivePlanId,
    required this.accessSource,
    this.effectiveStatus,
    this.currentPeriodEnd,
    required this.courtesy,
    required this.renewal,
  });

  factory EffectivePlanAccess.fromDto(EffectivePlanAccessDto dto) {
    final contracted = PlanosService.normalizePlanIdForAccess(
      dto.contractedPlanId ?? dto.effectivePlanId,
    );
    final effective = PlanosService.normalizePlanIdForAccess(
      dto.effectivePlanId ?? dto.contractedPlanId,
    );
    return EffectivePlanAccess(
      contractedPlanId: contracted,
      effectivePlanId: effective,
      accessSource: dto.accessSource ?? 'unknown',
      effectiveStatus: dto.effectiveStatus,
      currentPeriodEnd: _parseIso(dto.currentPeriodEnd),
      courtesy: dto.courtesy,
      renewal: dto.renewal,
    );
  }

  /// Fallback seguro quando o callable falha — nunca eleva acima do contratado.
  factory EffectivePlanAccess.fallbackContracted({
    required String contractedPlanId,
  }) {
    final normalized = PlanosService.normalizePlanIdForAccess(contractedPlanId);
    return EffectivePlanAccess(
      contractedPlanId: normalized,
      effectivePlanId: normalized,
      accessSource: 'contracted_fallback',
      courtesy: const MasterPlanCourtesySummary(active: false),
      renewal: const MasterPlanRenewalSummary(
        active: false,
        cancelAtPeriodEnd: false,
      ),
    );
  }

  PlanAccessTier get effectiveTier => PlanMatrix.tierForPlanId(effectivePlanId);

  bool get hasActiveCourtesy => courtesy.active;

  static DateTime? _parseIso(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
