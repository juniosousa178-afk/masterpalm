import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/release_evidence/release_attestation.dart';
import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_policy.dart';
import '../models/release_evidence/release_evidence_reference.dart';
import '../models/release_evidence/release_evidence_request.dart';
import '../models/release_evidence/release_verification_policy.dart';
import '../models/release_evidence/release_verification_result.dart';

/// Canonical serialization and fingerprinting for release evidence.
class ReleaseEvidenceCanonicalSerializer {
  const ReleaseEvidenceCanonicalSerializer();

  static const String version = 'release-evidence-canonical-v1';

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String policyFingerprint(ReleaseEvidencePolicy policy) {
    return fingerprintFromString(jsonEncode(policy.toComparableJson()));
  }

  String attestationPolicyFingerprint(ReleaseAttestationPolicy policy) {
    return fingerprintFromString(jsonEncode(_normalizeJson(policy.toJson())));
  }

  String verificationPolicyFingerprint(ReleaseVerificationPolicy policy) {
    return fingerprintFromString(jsonEncode(_normalizeJson(policy.toJson())));
  }

  String requestFingerprint(ReleaseEvidenceRequest request) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(request.toJson())),
    );
  }

  String bundleFingerprint(ReleaseEvidenceBundle bundle) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(_bundleComparableJson(bundle))),
    );
  }

  String attestationFingerprint(ReleaseAttestation attestation) {
    final json = attestation.toJson();
    final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
    metadata.remove('attestationId');
    metadata.remove('fingerprint');
    metadata.remove('createdAt');
    json['metadata'] = metadata;
    json.remove('fingerprint');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String verificationFingerprint(ReleaseVerificationResult result) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(_verificationComparableJson(result))),
    );
  }

  String sourceReferencesFingerprint(
    List<ReleaseEvidenceSourceReference> references,
  ) {
    final refs = references.map((r) => _normalizeJson(r.toJson())).toList()
      ..sort(
        (a, b) =>
            (a['sourceType'] as String).compareTo(b['sourceType'] as String),
      );
    return fingerprintFromString(jsonEncode(refs));
  }

  String sourceSetFingerprint(List<Map<String, dynamic>> sourceRefs) {
    final sorted = sourceRefs.map(_normalizeJson).toList()
      ..sort(
        (a, b) =>
            (a['sourceType'] as String).compareTo(b['sourceType'] as String),
      );
    return fingerprintFromString(jsonEncode(sorted));
  }

  Map<String, dynamic> _bundleComparableJson(ReleaseEvidenceBundle bundle) {
    final json = bundle.toJson();
    final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
    metadata.remove('bundleId');
    metadata.remove('fingerprint');
    metadata.remove('createdAt');
    metadata.remove('evaluatedAt');
    json['metadata'] = metadata;
    json.remove('fingerprint');
    final evidence = List<Map<String, dynamic>>.from(
      (json['evidence'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) =>
            (a['artifactReference'] as Map)['artifactId'].toString().compareTo(
                  (b['artifactReference'] as Map)['artifactId'].toString(),
                ),
      );
    json['evidence'] = evidence;
    final provenance = List<Map<String, dynamic>>.from(
      (json['provenance'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) => a['provenanceId']
            .toString()
            .compareTo(b['provenanceId'].toString()),
      );
    json['provenance'] = provenance;
    final attestations = List<Map<String, dynamic>>.from(
      (json['attestations'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) => (a['metadata'] as Map)['attestationId']
            .toString()
            .compareTo((b['metadata'] as Map)['attestationId'].toString()),
      );
    json['attestations'] = attestations;
    return json;
  }

  Map<String, dynamic> _verificationComparableJson(
    ReleaseVerificationResult result,
  ) {
    final json = result.toJson();
    json.remove('verificationId');
    json.remove('fingerprint');
    json.remove('evaluatedAt');
    final checks = List<Map<String, dynamic>>.from(
      (json['checks'] as List).cast<Map<String, dynamic>>(),
    )..sort(
        (a, b) => a['checkId'].toString().compareTo(b['checkId'].toString()),
      );
    json['checks'] = checks;
    return json;
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
    if (value is double) {
      if (value.isNaN || value.isInfinite) {
        throw FormatException('Non-finite value in canonicalization');
      }
      if (value == -0.0) return 0.0;
      return value;
    }
    return value;
  }
}
