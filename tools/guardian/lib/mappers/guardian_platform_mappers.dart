import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../models/guardian_result.dart';
import '../models/impact_result.dart';
import '../models/risk_result.dart';

/// Maps Guardian-local models to immutable Platform DTOs.
class GuardianPlatformMappers {
  const GuardianPlatformMappers._();

  static ChangeImpact toChangeImpact(ImpactResult impact) {
    return ChangeImpact(
      domains: List<String>.from(impact.domains),
      affectedFiles: List<String>.from(impact.services),
      affectedMethods: const [],
      relatedServices: List<String>.from(impact.services),
      metadata: {
        'screens': impact.screens.join(','),
        'firestore_collections': impact.firestoreCollections.join(','),
        'hive_boxes': impact.hiveBoxes.join(','),
        'flows': impact.flows.join(','),
        'related_rcas': impact.relatedRcas.join(','),
        'related_runbooks': impact.relatedRunbooks.join(','),
      },
    );
  }

  static PlatformRiskResult toPlatformRisk(RiskResult risk) {
    return PlatformRiskResult(
      overall: _mapRiskLevel(risk.overall),
      items: risk.items
          .map(
            (item) => PlatformRiskItem(
              id: item.file,
              level: _mapRiskLevel(item.level),
              message: item.reason,
              source: item.method,
            ),
          )
          .toList(),
    );
  }

  static AnalysisResult toAnalysisResult(GuardianResult result) {
    return AnalysisResult(
      success: result.decision == GuardianDecision.go,
      summary: result.summary,
      details: {
        'decision': result.decision.name,
        'impact': toChangeImpact(result.impact).toJson(),
        'risk': toPlatformRisk(result.risk).toJson(),
        'guardian': result.toJson(),
      },
      warnings: result.violations
          .where((v) => v.severity.name != 'info')
          .map((v) => '${v.code}: ${v.message}')
          .toList(),
    );
  }

  static PlatformRiskLevel _mapRiskLevel(RiskLevel level) {
    switch (level) {
      case RiskLevel.green:
        return PlatformRiskLevel.low;
      case RiskLevel.yellow:
        return PlatformRiskLevel.medium;
      case RiskLevel.red:
        return PlatformRiskLevel.high;
      case RiskLevel.blocking:
        return PlatformRiskLevel.critical;
    }
  }
}
