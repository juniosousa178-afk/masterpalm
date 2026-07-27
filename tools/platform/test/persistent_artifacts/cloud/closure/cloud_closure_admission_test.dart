import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../hardening/support/cloud_hardening_helpers.dart';

void main() {
  group('CloudClosureAdmissionBaseline', () {
    const evaluator = PersistentArtifactRealCloudAdapterAdmissionEvaluator();

    test('baseline golden matches real evaluator state', () {
      final decision = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(),
      );
      final snapshot = {
        'name': 'real-adapter-admission-baseline',
        'decisionStatus': decision.status.wireName,
        'criteriaCount': decision.totalCriteriaCount,
        'approvedCriteriaCount': decision.satisfiedCriteriaCount,
        'missingCriteriaCount': decision.missingCriteria.length,
        'manualApprovalReferencePresent':
            decision.manualApprovalReference != null,
        'eligibleForDesignReview': decision.status ==
            RealCloudAdapterAdmissionStatus.eligibleForDesignReview,
        'approvedForPrototype': decision.prototypeAdmissionGranted,
        'stagingApproved': decision.stagingApproved,
        'productionApproved': decision.productionApproved,
        'realAdapterWorkAuthorized': false,
        'issueCount': decision.issues.length,
      };

      final golden = jsonDecode(
        File('test/goldens/persistent_artifacts/cloud_closure/'
                'real_adapter_admission_baseline.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(snapshot['decisionStatus'], golden['decisionStatus']);
      expect(snapshot['approvedForPrototype'], isFalse);
      expect(snapshot['stagingApproved'], isFalse);
      expect(snapshot['productionApproved'], isFalse);
      expect(snapshot['realAdapterWorkAuthorized'], isFalse);
      expect(snapshot['criteriaCount'], 31);
      expect(snapshot['approvedCriteriaCount'], 0);
    });
  });

  group('CloudClosureAdmissionExhaustive', () {
    const evaluator = PersistentArtifactRealCloudAdapterAdmissionEvaluator();

    test('zero criteria => notEvaluated', () {
      final d = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(),
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.notEvaluated);
      expect(d.stagingApproved, isFalse);
      expect(d.productionApproved, isFalse);
    });

    test('one criterion => incomplete', () {
      final d = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(
          targetProviderSelected: true,
        ),
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.incomplete);
    });

    test('partial criteria => incomplete', () {
      final d = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(
          targetProviderSelected: true,
          protocolSpecificationReviewed: true,
          officialSdkDecisionRecorded: true,
        ),
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.incomplete);
      expect(d.missingCriteria.length, greaterThan(0));
    });

    test('all criteria without manual approval => eligibleForDesignReview', () {
      final d =
          evaluator.evaluate(criteria: CloudHardeningHelpers.allCriteriaMet());
      expect(d.status, RealCloudAdapterAdmissionStatus.eligibleForDesignReview);
      expect(d.prototypeAdmissionGranted, isFalse);
    });

    test('all criteria with empty manual approval => eligibleForDesignReview',
        () {
      final d = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
        manualApprovalReference: '',
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.eligibleForDesignReview);
    });

    test(
        'all criteria with whitespace manual approval => eligibleForDesignReview',
        () {
      final d = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
        manualApprovalReference: '   ',
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.eligibleForDesignReview);
    });

    test('manual approval without criteria => notEvaluated', () {
      final d = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(),
        manualApprovalReference: 'AR-REF-1',
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.notEvaluated);
      expect(d.prototypeAdmissionGranted, isFalse);
    });

    test('manual approval with partial criteria => incomplete', () {
      final d = evaluator.evaluate(
        criteria: const PersistentArtifactRealCloudAdapterAdmissionCriteria(
          targetProviderSelected: true,
        ),
        manualApprovalReference: 'AR-REF-1',
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.incomplete);
    });

    test('complete criteria and valid reference => approvedForPrototype', () {
      final d = evaluator.evaluate(
        criteria: CloudHardeningHelpers.allCriteriaMet(),
        manualApprovalReference: 'AR-025-MANUAL-APPROVAL-REF',
      );
      expect(d.status, RealCloudAdapterAdmissionStatus.approvedForPrototype);
      expect(d.stagingApproved, isFalse);
      expect(d.productionApproved, isFalse);
    });

    test('evaluator is deterministic for same input', () {
      const criteria = PersistentArtifactRealCloudAdapterAdmissionCriteria(
        targetProviderSelected: true,
      );
      final a = evaluator.evaluate(criteria: criteria);
      final b = evaluator.evaluate(criteria: criteria);
      expect(a.toComparableJson(), b.toComparableJson());
    });

    test('31 criterion ids are stable', () {
      expect(
        PersistentArtifactRealCloudAdapterAdmissionCriteria.criterionIds.length,
        31,
      );
      expect(
        const PersistentArtifactRealCloudAdapterAdmissionCriteria()
            .missingCriterionIds()
            .length,
        31,
      );
    });
  });
}
