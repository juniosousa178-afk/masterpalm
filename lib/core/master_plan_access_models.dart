// Modelos DTO para Tela Mestre de planos e acesso efetivo.

class MasterPlanCourtesySummary {
  final bool active;
  final String? planId;
  final String? type;
  final String? startsAt;
  final String? expiresAt;
  final bool permanent;

  const MasterPlanCourtesySummary({
    required this.active,
    this.planId,
    this.type,
    this.startsAt,
    this.expiresAt,
    this.permanent = false,
  });

  factory MasterPlanCourtesySummary.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const MasterPlanCourtesySummary(active: false);
    }
    return MasterPlanCourtesySummary(
      active: map['active'] == true,
      planId: map['planId']?.toString(),
      type: map['type']?.toString(),
      startsAt: map['startsAt']?.toString(),
      expiresAt: map['expiresAt']?.toString(),
      permanent: map['permanent'] == true,
    );
  }
}

class MasterPlanRenewalSummary {
  final bool active;
  final bool cancelAtPeriodEnd;

  const MasterPlanRenewalSummary({
    required this.active,
    required this.cancelAtPeriodEnd,
  });

  factory MasterPlanRenewalSummary.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const MasterPlanRenewalSummary(active: false, cancelAtPeriodEnd: false);
    }
    return MasterPlanRenewalSummary(
      active: map['active'] == true,
      cancelAtPeriodEnd: map['cancelAtPeriodEnd'] == true,
    );
  }
}

class MasterPlanUserRow {
  final String uid;
  final String? emailMasked;
  final String? lojaId;
  final String? lojaNome;
  final String? contractedPlanId;
  final String? effectivePlanId;
  final String? accessSource;
  final String? effectiveStatus;
  final String? currentPeriodEnd;
  final int? daysRemaining;
  final MasterPlanRenewalSummary renewal;
  final MasterPlanCourtesySummary courtesy;

  const MasterPlanUserRow({
    required this.uid,
    this.emailMasked,
    this.lojaId,
    this.lojaNome,
    this.contractedPlanId,
    this.effectivePlanId,
    this.accessSource,
    this.effectiveStatus,
    this.currentPeriodEnd,
    this.daysRemaining,
    required this.renewal,
    required this.courtesy,
  });

  factory MasterPlanUserRow.fromMap(Map<String, dynamic> map) {
    final store = map['store'] is Map ? map['store'] as Map : const {};
    return MasterPlanUserRow(
      uid: map['uid']?.toString() ?? '',
      emailMasked: map['emailMasked']?.toString(),
      lojaId: store['lojaId']?.toString(),
      lojaNome: store['nome']?.toString(),
      contractedPlanId: map['contractedPlanId']?.toString(),
      effectivePlanId: map['effectivePlanId']?.toString(),
      accessSource: map['accessSource']?.toString(),
      effectiveStatus: map['effectiveStatus']?.toString(),
      currentPeriodEnd: map['currentPeriodEnd']?.toString(),
      daysRemaining: map['daysRemaining'] is num
          ? (map['daysRemaining'] as num).toInt()
          : int.tryParse('${map['daysRemaining']}'),
      renewal: MasterPlanRenewalSummary.fromMap(
        map['renewal'] is Map ? Map<String, dynamic>.from(map['renewal'] as Map) : null,
      ),
      courtesy: MasterPlanCourtesySummary.fromMap(
        map['courtesy'] is Map ? Map<String, dynamic>.from(map['courtesy'] as Map) : null,
      ),
    );
  }
}

class MasterPlanAccessSummary {
  final int? totalCanonicalUsers;
  final Map<String, int?> totalByContractedPlan;
  final int? totalRenewalCancelled;
  final int? totalActiveCourtesy;
  final bool totalActiveCourtesyPending;
  final bool manualGrantPending;
  final int? manualOverrideCount;
  final bool manualOverridePending;

  const MasterPlanAccessSummary({
    this.totalCanonicalUsers,
    this.totalByContractedPlan = const {},
    this.totalRenewalCancelled,
    this.totalActiveCourtesy,
    this.totalActiveCourtesyPending = false,
    this.manualGrantPending = true,
    this.manualOverrideCount,
    this.manualOverridePending = false,
  });

  factory MasterPlanAccessSummary.fromMap(Map<String, dynamic> map) {
    final byPlanRaw = map['totalByContractedPlan'];
    final byPlan = <String, int?>{};
    if (byPlanRaw is Map) {
      for (final e in byPlanRaw.entries) {
        final v = e.value;
        byPlan[e.key.toString()] = v is num ? v.toInt() : int.tryParse('$v');
      }
    }
    final mg = map['totalWithManualGrantLegacy'];
    final mo = map['totalWithManualOverrideLegacy'];
    return MasterPlanAccessSummary(
      totalCanonicalUsers: map['totalCanonicalUsers'] is num
          ? (map['totalCanonicalUsers'] as num).toInt()
          : int.tryParse('${map['totalCanonicalUsers']}'),
      totalByContractedPlan: byPlan,
      totalRenewalCancelled: map['totalRenewalCancelled'] is num
          ? (map['totalRenewalCancelled'] as num).toInt()
          : int.tryParse('${map['totalRenewalCancelled']}'),
      totalActiveCourtesy: map['totalActiveCourtesy'] is num
          ? (map['totalActiveCourtesy'] as num).toInt()
          : int.tryParse('${map['totalActiveCourtesy']}'),
      totalActiveCourtesyPending: map['totalActiveCourtesyPendingImplementation'] == true,
      manualGrantPending: mg is Map && mg['pendingImplementation'] == true,
      manualOverrideCount: mo is Map && mo['count'] is num
          ? (mo['count'] as num).toInt()
          : int.tryParse('${mo is Map ? mo['count'] : null}'),
      manualOverridePending: mo is Map && mo['pendingImplementation'] == true,
    );
  }
}

/// Bloco `subscription` já sanitizado pelo callable (sem preapproval completo).
class PlanAccessSubscriptionSummary {
  final String? provider;
  final String? paymentMethodLabel;
  final String? maskedProviderSubscriptionId;

  const PlanAccessSubscriptionSummary({
    this.provider,
    this.paymentMethodLabel,
    this.maskedProviderSubscriptionId,
  });

  factory PlanAccessSubscriptionSummary.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PlanAccessSubscriptionSummary();
    return PlanAccessSubscriptionSummary(
      provider: map['provider']?.toString(),
      paymentMethodLabel: map['paymentMethodLabel']?.toString(),
      maskedProviderSubscriptionId:
          map['maskedProviderSubscriptionId']?.toString(),
    );
  }

  bool get hasMaskedSubscriptionId {
    final id = maskedProviderSubscriptionId?.trim() ?? '';
    return id.isNotEmpty;
  }
}

class EffectivePlanAccessDto {
  final String? contractedPlanId;
  final String? effectivePlanId;
  final String? accessSource;
  final String? effectiveStatus;
  final String? currentPeriodEnd;
  final int? daysRemaining;
  final MasterPlanCourtesySummary courtesy;
  final MasterPlanRenewalSummary renewal;
  final String? blockedReason;
  final PlanAccessSubscriptionSummary subscription;

  const EffectivePlanAccessDto({
    this.contractedPlanId,
    this.effectivePlanId,
    this.accessSource,
    this.effectiveStatus,
    this.currentPeriodEnd,
    this.daysRemaining,
    required this.courtesy,
    required this.renewal,
    this.blockedReason,
    this.subscription = const PlanAccessSubscriptionSummary(),
  });

  factory EffectivePlanAccessDto.fromMap(Map<String, dynamic> map) {
    return EffectivePlanAccessDto(
      contractedPlanId: map['contractedPlanId']?.toString(),
      effectivePlanId: map['effectivePlanId']?.toString(),
      accessSource: map['accessSource']?.toString(),
      effectiveStatus: map['effectiveStatus']?.toString(),
      currentPeriodEnd: map['currentPeriodEnd']?.toString(),
      daysRemaining: map['daysRemaining'] is num
          ? (map['daysRemaining'] as num).toInt()
          : int.tryParse('${map['daysRemaining']}'),
      courtesy: MasterPlanCourtesySummary.fromMap(
        map['courtesy'] is Map ? Map<String, dynamic>.from(map['courtesy'] as Map) : null,
      ),
      renewal: MasterPlanRenewalSummary.fromMap(
        map['renewal'] is Map ? Map<String, dynamic>.from(map['renewal'] as Map) : null,
      ),
      blockedReason: map['blockedReason']?.toString(),
      subscription: PlanAccessSubscriptionSummary.fromMap(
        map['subscription'] is Map
            ? Map<String, dynamic>.from(map['subscription'] as Map)
            : null,
      ),
    );
  }

  bool get hasActiveCourtesy => courtesy.active;
}

class MasterPlanAuditAction {
  final String actionId;
  final String? actionType;
  final String? reason;
  final String? createdAt;
  final Map<String, dynamic>? beforeSnapshot;
  final Map<String, dynamic>? afterSnapshot;

  const MasterPlanAuditAction({
    required this.actionId,
    this.actionType,
    this.reason,
    this.createdAt,
    this.beforeSnapshot,
    this.afterSnapshot,
  });

  factory MasterPlanAuditAction.fromMap(String id, Map<String, dynamic> map) {
    return MasterPlanAuditAction(
      actionId: id,
      actionType: map['actionType']?.toString(),
      reason: map['reason']?.toString(),
      createdAt: map['createdAt']?.toString(),
      beforeSnapshot: map['beforeSnapshot'] is Map
          ? Map<String, dynamic>.from(map['beforeSnapshot'] as Map)
          : null,
      afterSnapshot: map['afterSnapshot'] is Map
          ? Map<String, dynamic>.from(map['afterSnapshot'] as Map)
          : null,
    );
  }
}
