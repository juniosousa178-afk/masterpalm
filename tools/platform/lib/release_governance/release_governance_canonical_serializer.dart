import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_request.dart';

/// Canonical serialization and fingerprinting for release governance.
class ReleaseGovernanceCanonicalSerializer {
  const ReleaseGovernanceCanonicalSerializer();

  static const String version = 'release-governance-canonical-v1';

  String fingerprintFromString(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String policyFingerprint(ReleaseGovernancePolicy policy) {
    return fingerprintFromString(jsonEncode(policy.toComparableJson()));
  }

  String requestFingerprint(ReleaseGovernanceRequest request) {
    final json = request.toJson();
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String evaluationFingerprint(ReleaseGovernanceEvaluation evaluation) {
    final json = evaluation.toJson()..remove('fingerprint');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String approvalEvaluationFingerprint(ReleaseApprovalEvaluation evaluation) {
    final json = evaluation.toJson()..remove('fingerprint');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String waiverEvaluationFingerprint(ReleaseWaiverEvaluation evaluation) {
    final json = evaluation.toJson()..remove('fingerprint');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String conditionFingerprint(ReleaseCondition condition) {
    final json = condition.toJson()..remove('fingerprint');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String sourceReferencesFingerprint(
    List<ReleaseGovernanceSourceReference> references,
  ) {
    final refs = references.map((r) => _normalizeJson(r.toJson())).toList()
      ..sort(
        (a, b) =>
            (a['sourceType'] as String).compareTo(b['sourceType'] as String),
      );
    return fingerprintFromString(jsonEncode(refs));
  }

  String evidenceFingerprint(ReleaseGovernanceEvidence evidence) {
    final json = evidence.toJson()..remove('evidenceId');
    return fingerprintFromString(jsonEncode(_normalizeJson(json)));
  }

  String snapshotFingerprint(ReleaseDecisionSnapshot snapshot) {
    return fingerprintFromString(
      jsonEncode(_normalizeJson(_snapshotComparableJson(snapshot))),
    );
  }

  String sourceSetFingerprint(List<Map<String, dynamic>> sourceRefs) {
    final sorted = sourceRefs.map(_normalizeJson).toList()
      ..sort((a, b) =>
          (a['sourceType'] as String).compareTo(b['sourceType'] as String));
    return fingerprintFromString(jsonEncode(sorted));
  }

  Map<String, dynamic> _snapshotComparableJson(
      ReleaseDecisionSnapshot snapshot) {
    final json = snapshot.toJson();
    final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
    metadata.remove('snapshotId');
    metadata.remove('releaseGovernanceFingerprint');
    metadata.remove('createdAt');
    metadata.remove('evaluatedAt');
    json['metadata'] = metadata;
    json.remove('fingerprint');
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
