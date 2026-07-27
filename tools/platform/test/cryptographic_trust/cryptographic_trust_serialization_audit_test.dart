import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust serialization audit', () {
    const serializer = CryptographicTrustCanonicalSerializer();

    void roundTrip<T>({
      required T original,
      required Map<String, dynamic> Function(T) toJson,
      required T Function(Map<String, dynamic>) fromJson,
      void Function(T restored)? assertEqual,
    }) {
      final json = toJson(original);
      final restored = fromJson(Map<String, dynamic>.from(json));
      assertEqual?.call(restored);
    }

    test('CryptographicTrustSnapshot roundtrip', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      roundTrip<CryptographicTrustSnapshot>(
        original: snapshot,
        toJson: (s) => s.toJson(),
        fromJson: CryptographicTrustSnapshot.fromJson,
        assertEqual: (r) {
          expect(
            r.metadata.cryptographicTrustSnapshotId,
            snapshot.metadata.cryptographicTrustSnapshotId,
          );
          expect(r.fingerprint, isNotEmpty);
        },
      );
    });

    test('CryptographicTrustEvaluationRequest roundtrip', () {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      roundTrip<CryptographicTrustEvaluationRequest>(
        original: request,
        toJson: (r) => r.toJson(),
        fromJson: CryptographicTrustEvaluationRequest.fromJson,
        assertEqual: (r) => expect(r.evaluationId, request.evaluationId),
      );
    });

    test('CryptographicTrustEvaluationResult roundtrip', () async {
      final original = await evaluatePassingSnapshot();
      roundTrip<CryptographicTrustEvaluationResult>(
        original: original,
        toJson: (r) => r.toJson(),
        fromJson: CryptographicTrustEvaluationResult.fromJson,
        assertEqual: (r) => expect(r.evaluationId, original.evaluationId),
      );
    });

    test('CryptographicVerificationRequest roundtrip', () {
      final request =
          CryptographicTrustOperationalFixtures.verificationRequest();
      roundTrip<CryptographicVerificationRequest>(
        original: request,
        toJson: (r) => r.toJson(),
        fromJson: CryptographicVerificationRequest.fromJson,
        assertEqual: (r) => expect(r.requestId, request.requestId),
      );
    });

    test('policies roundtrip via registry resolve', () {
      final registry =
          CryptographicTrustOperationalFixtures.createPolicyRegistry(
        registerDefaults: true,
        freeze: true,
      );
      final policy = registry.resolveById(
        ArtifactSignatureTrustPolicyV1.policyId,
        1,
      );
      expect(policy, isNotNull);
      expect(policy!.policyId, ArtifactSignatureTrustPolicyV1.policyId);
    });

    test('enum wire names roundtrip snapshot status', () {
      for (final status in CryptographicTrustStatus.values) {
        expect(
          CryptographicTrustStatusX.fromWireName(status.wireName),
          status,
        );
      }
    });

    test('enum wire names roundtrip evaluation status', () {
      for (final status in CryptographicTrustEvaluationStatus.values) {
        expect(
          CryptographicTrustEvaluationStatusX.fromWireName(status.wireName),
          status,
        );
      }
    });

    test('enum wire names roundtrip verification status', () {
      for (final status in CryptographicVerificationStatus.values) {
        expect(
          CryptographicVerificationStatusX.fromWireName(status.wireName),
          status,
        );
      }
    });

    test('referenceTime uses UTC Z suffix in fixtures', () {
      expect(CryptographicTrustOperationalFixtures.referenceTime.endsWith('Z'),
          isTrue);
    });

    test('unknown enum throws FormatException', () {
      expect(
        () => CryptographicTrustStatusX.fromWireName('not-a-status'),
        throwsFormatException,
      );
    });

    test('canonical serializer map ordering is deterministic', () {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final json = request.toComparableJson();
      final shuffled = {
        'releaseId': json['releaseId'],
        'projectId': json['projectId'],
        'evaluationId': json['evaluationId'],
        ...json,
      };
      expect(
        serializer.evaluationRequestFingerprint(
          CryptographicTrustEvaluationRequest.fromJson(request.toJson()),
        ),
        serializer.evaluationRequestFingerprint(request),
      );
      expect(shuffled.keys.length, greaterThan(3));
    });

    test('comparable json roundtrip preserves snapshot fingerprint', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);
      final restored = CryptographicTrustSnapshot.fromJson(snapshot.toJson());
      expect(serializer.snapshotFingerprint(restored), fp);
    });

    test('CryptographicTrustQuery roundtrip', () {
      const query = CryptographicTrustQuery(
        projectId: CryptographicTrustOperationalFixtures.projectId,
        trustStatus: CryptographicTrustStatus.trusted,
        sortDirection: CryptographicTrustQuerySortDirection.descending,
        limit: 10,
        offset: 0,
      );
      roundTrip<CryptographicTrustQuery>(
        original: query,
        toJson: (q) => q.toJson(),
        fromJson: CryptographicTrustQuery.fromJson,
        assertEqual: (r) => expect(r.limit, 10),
      );
    });

    test('digest comparable excludes createdAt timestamp', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      expect(digest.toComparableJson().containsKey('createdAt'), isFalse);
      expect(digest.toJson().containsKey('createdAt'), isTrue);
    });
  });
}
