import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_trust_identity.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import 'cryptographic_trust_canonical_serializer.dart';

/// Builds deterministic cryptographic trust identities and fingerprints.
class CryptographicTrustIdentityBuilder {
  const CryptographicTrustIdentityBuilder({
    CryptographicTrustCanonicalSerializer? serializer,
  }) : _serializer =
            serializer ?? const CryptographicTrustCanonicalSerializer();

  final CryptographicTrustCanonicalSerializer _serializer;

  String buildCryptographicTrustId({
    required String projectId,
    required String releaseId,
    required String policyId,
    required int policyVersion,
    required String snapshotFingerprint,
    required int schemaVersion,
  }) {
    return 'cryptographic-trust:$projectId:$releaseId:$policyId:$policyVersion:$snapshotFingerprint:$schemaVersion';
  }

  String buildCryptographicTrustIdFromSnapshot(
    CryptographicTrustSnapshot snapshot,
  ) {
    final policy =
        snapshot.trustPolicies.isNotEmpty ? snapshot.trustPolicies.first : null;
    return buildCryptographicTrustId(
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId ?? 'unknown',
      policyId: policy?.policyId ?? 'unknown',
      policyVersion: policy?.version ?? 0,
      snapshotFingerprint: snapshot.fingerprint,
      schemaVersion: snapshot.metadata.schemaVersion,
    );
  }

  String buildSnapshotId({
    required String projectId,
    required String releaseId,
    required String snapshotFingerprint,
  }) {
    return 'ct-snapshot:$projectId:$releaseId:$snapshotFingerprint';
  }

  String buildSnapshotIdFromSnapshot(CryptographicTrustSnapshot snapshot) {
    return buildSnapshotId(
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId ?? 'unknown',
      snapshotFingerprint: snapshot.fingerprint,
    );
  }

  String buildVerificationIdFromResult(CryptographicVerificationResult result) {
    final fingerprint = verificationFingerprintForResult(result);
    return 'ct-verify:${result.requestId}:$fingerprint';
  }

  String subjectsFingerprint(CollectedCryptographicTrustMaterial material) {
    if (material.subjects.isEmpty) return '';
    final comparable =
        material.subjects.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) =>
                a['subjectId'].toString().compareTo(b['subjectId'].toString()),
          );
    return _serializer.fingerprintFromString(comparable.toString());
  }

  String signaturesFingerprint(CollectedCryptographicTrustMaterial material) {
    if (material.signatures.isEmpty) return '';
    return _serializer.signaturesFingerprint(
      material.signatures.map((e) => e.toComparableJson()).toList(),
    );
  }

  String attestationsFingerprint(CollectedCryptographicTrustMaterial material) {
    if (material.attestations.isEmpty) return '';
    return _serializer.attestationsFingerprint(
      material.attestations.map((e) => e.toComparableJson()).toList(),
    );
  }

  String policiesFingerprint(CollectedCryptographicTrustMaterial material) {
    if (material.policies.isEmpty) return '';
    return _serializer.policiesFingerprint(
      material.policies.map((e) => e.toComparableJson()).toList(),
    );
  }

  String trustChainsFingerprint(CollectedCryptographicTrustMaterial material) {
    if (material.trustChains.isEmpty) return '';
    return _serializer.trustChainsFingerprint(
      material.trustChains.map((e) => e.toComparableJson()).toList(),
    );
  }

  String verificationFingerprintForResult(
    CryptographicVerificationResult result,
  ) {
    return _serializer.verificationResultFingerprint(result);
  }

  String fingerprintForSnapshot(CryptographicTrustSnapshot snapshot) {
    return _serializer.snapshotContentFingerprint(snapshot);
  }

  CryptographicTrustIdentity buildIdentity({
    required CryptographicTrustSnapshot snapshot,
    required CollectedCryptographicTrustMaterial material,
    required CryptographicVerificationResult? verificationResult,
  }) {
    final snapshotFingerprint = snapshot.fingerprint;
    return CryptographicTrustIdentity(
      cryptographicTrustId: buildCryptographicTrustIdFromSnapshot(snapshot),
      subjectsFingerprint: subjectsFingerprint(material).isEmpty
          ? null
          : subjectsFingerprint(material),
      signaturesFingerprint: signaturesFingerprint(material).isEmpty
          ? null
          : signaturesFingerprint(material),
      attestationsFingerprint: attestationsFingerprint(material).isEmpty
          ? null
          : attestationsFingerprint(material),
      policiesFingerprint: policiesFingerprint(material).isEmpty
          ? null
          : policiesFingerprint(material),
      trustChainsFingerprint: trustChainsFingerprint(material).isEmpty
          ? null
          : trustChainsFingerprint(material),
      verificationFingerprint: verificationResult == null
          ? null
          : verificationFingerprintForResult(verificationResult),
      snapshotFingerprint: snapshotFingerprint,
    );
  }
}
