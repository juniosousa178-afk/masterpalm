import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_hardening_helpers.dart';

void main() {
  group('CloudHardeningAdmissionGate', () {
    const evaluator = PersistentArtifactRealCloudAdapterAdmissionEvaluator();

    test('notEvaluated when no criteria satisfied', () {
      final decision = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(),
      );
      expect(decision.status, RealCloudAdapterAdmissionStatus.notEvaluated);
      expect(decision.stagingApproved, isFalse);
      expect(decision.productionApproved, isFalse);
      expect(decision.prototypeAdmissionGranted, isFalse);
    });

    test('incomplete when partial criteria satisfied', () {
      final decision = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(
          targetProviderSelected: true,
          protocolSpecificationReviewed: true,
        ),
      );
      expect(decision.status, RealCloudAdapterAdmissionStatus.incomplete);
      expect(decision.missingCriteria, isNotEmpty);
    });

    test('eligibleForDesignReview when all criteria without manual approval',
        () {
      final decision = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
      );
      expect(
        decision.status,
        RealCloudAdapterAdmissionStatus.eligibleForDesignReview,
      );
      expect(decision.prototypeAdmissionGranted, isFalse);
    });

    test('approvedForPrototype requires manual approval reference', () {
      final decision = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
        manualApprovalReference: 'AR-025-manual-approval',
      );
      expect(
        decision.status,
        RealCloudAdapterAdmissionStatus.approvedForPrototype,
      );
      expect(decision.prototypeAdmissionGranted, isTrue);
      expect(decision.stagingApproved, isFalse);
      expect(decision.productionApproved, isFalse);
    });

    test('blocked and rejected statuses', () {
      final blocked = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
        blocked: true,
      );
      expect(blocked.status, RealCloudAdapterAdmissionStatus.blocked);

      final rejected = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
        rejected: true,
      );
      expect(rejected.status, RealCloudAdapterAdmissionStatus.rejected);
    });

    test('serialization roundtrip preserves comparable decision', () {
      final decision = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
        manualApprovalReference: 'manual-ref-1',
      );
      final restored =
          PersistentArtifactRealCloudAdapterAdmissionDecision.fromJson(
              decision.toJson());
      expect(
        restored.toComparableJson(),
        decision.toComparableJson(),
      );
    });
  });
}
