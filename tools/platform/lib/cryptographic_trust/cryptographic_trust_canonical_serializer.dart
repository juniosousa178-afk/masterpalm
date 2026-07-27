import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import '../models/cryptographic_trust/cryptographic_trust_identity.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_trust_source_reference.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';

/// Canonical serialization and fingerprinting for cryptographic trust.
class CryptographicTrustCanonicalSerializer {
  const CryptographicTrustCanonicalSerializer();

  static const String version = 'cryptographic-trust-canonical-v1';

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String evaluationRequestFingerprint(
    CryptographicTrustEvaluationRequest request,
  ) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(request.toComparableJson())),
    );
  }

  String resolvedSourcesFingerprint(ResolvedCryptographicTrustSources sources) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(sources.toComparableJson())),
    );
  }

  String collectedMaterialFingerprint(
    CollectedCryptographicTrustMaterial material,
  ) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(material.toComparableJson())),
    );
  }

  String digestFingerprint(CryptographicDigest digest) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(digest.toComparableJson())),
    );
  }

  String digestsFingerprint(List<CryptographicDigest> digests) {
    final comparable = digests.map((e) => e.toComparableJson()).toList()
      ..sort(
        (a, b) =>
            a['subjectId'].toString().compareTo(b['subjectId'].toString()),
      );
    return fingerprintFromString(
        jsonEncode(_normalizeJson({'digests': comparable})));
  }

  String signaturesFingerprint(
    List<Map<String, dynamic>> comparableSignatures,
  ) {
    final sorted = List<Map<String, dynamic>>.from(comparableSignatures)
      ..sort(
        (a, b) =>
            a['signatureId'].toString().compareTo(b['signatureId'].toString()),
      );
    return fingerprintFromString(
        jsonEncode(_normalizeJson({'signatures': sorted})));
  }

  String attestationsFingerprint(
    List<Map<String, dynamic>> comparableAttestations,
  ) {
    final sorted = List<Map<String, dynamic>>.from(comparableAttestations)
      ..sort(
        (a, b) => a['attestationId']
            .toString()
            .compareTo(b['attestationId'].toString()),
      );
    return fingerprintFromString(
      jsonEncode(_normalizeJson({'attestations': sorted})),
    );
  }

  String policiesFingerprint(List<Map<String, dynamic>> comparablePolicies) {
    final sorted = List<Map<String, dynamic>>.from(comparablePolicies)
      ..sort(
        (a, b) => a['policyId'].toString().compareTo(b['policyId'].toString()),
      );
    return fingerprintFromString(
        jsonEncode(_normalizeJson({'policies': sorted})));
  }

  String trustChainsFingerprint(
    List<Map<String, dynamic>> comparableTrustChains,
  ) {
    final sorted = List<Map<String, dynamic>>.from(comparableTrustChains)
      ..sort(
        (a, b) => a['trustChainId']
            .toString()
            .compareTo(b['trustChainId'].toString()),
      );
    return fingerprintFromString(
      jsonEncode(_normalizeJson({'trustChains': sorted})),
    );
  }

  String verificationResultFingerprint(
    CryptographicVerificationResult result,
  ) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(result.toComparableJson())),
    );
  }

  String policyResultsFingerprint(
    List<CryptographicPolicyVerificationResult> results,
  ) {
    final comparable = results.map((e) => e.toComparableJson()).toList()
      ..sort(
        (a, b) => a['policyId'].toString().compareTo(b['policyId'].toString()),
      );
    return fingerprintFromString(
      jsonEncode(_normalizeJson({'policyResults': comparable})),
    );
  }

  String snapshotFingerprint(CryptographicTrustSnapshot snapshot) {
    return snapshotContentFingerprint(snapshot);
  }

  /// Fingerprint of snapshot canonical content excluding [CryptographicTrustIdentity].
  ///
  /// Identity references the snapshot fingerprint and must not participate in it.
  String snapshotContentFingerprint(CryptographicTrustSnapshot snapshot) {
    final comparable = Map<String, dynamic>.from(snapshot.toComparableJson());
    comparable.remove('identity');
    return fingerprintFromString(jsonEncode(_normalizeJson(comparable)));
  }

  String identityFingerprint(CryptographicTrustIdentity identity) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(identity.toComparableJson())),
    );
  }

  String sourceReferencesFingerprint(
    List<CryptographicTrustSourceReference> references,
  ) {
    final refs = references.map((r) => r.toComparableJson()).toList()
      ..sort(
        (a, b) => a['sourceId'].toString().compareTo(b['sourceId'].toString()),
      );
    return fingerprintFromString(jsonEncode(_normalizeJson({'sources': refs})));
  }

  Map<String, dynamic> _normalizeJson(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    final keys = input.keys.toList()..sort();
    for (final key in keys) {
      output[key] = _normalizeValue(input[key]);
    }
    return output;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _normalizeJson(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    return value;
  }
}
