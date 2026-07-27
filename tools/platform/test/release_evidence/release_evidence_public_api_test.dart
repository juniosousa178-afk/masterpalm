import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('Release Evidence public API review', () {
    test('core provider types are exported', () {
      expect(ReleaseEvidencePolicyV1.policyId, 'release-evidence-v1');
      expect(ReleaseAttestationPolicyV1.policyId, 'release-attestation-v1');
      expect(ReleaseVerificationPolicyV1.policyId, 'release-verification-v1');
    });

    test('store and provider interfaces are public', () {
      expect(ReleaseEvidenceStore, isNotNull);
      expect(ReleaseEvidenceProvider, isNotNull);
      expect(InMemoryReleaseEvidenceStore, isNotNull);
      expect(PlatformReleaseEvidenceProvider, isNotNull);
    });

    test('bootstrap is exported', () {
      expect(ReleaseEvidencePlatformBootstrap, isNotNull);
    });

    test('validators are exported for consumer validation', () {
      expect(ReleaseEvidenceBundleValidator, isNotNull);
      expect(ReleaseAttestationValidator, isNotNull);
      expect(ReleaseVerificationResultValidator, isNotNull);
    });
  });
}
