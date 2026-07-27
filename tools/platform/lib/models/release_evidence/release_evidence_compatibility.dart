import 'release_evidence_enums.dart';
import 'release_evidence_reference.dart';

/// Individual compatibility check for release evidence sources.
class ReleaseEvidenceCompatibilityCheck {
  const ReleaseEvidenceCompatibilityCheck({
    required this.checkId,
    required this.checkType,
    required this.status,
    this.expected,
    this.actual,
    this.reasons = const [],
    this.sourceReference,
    this.limitations = const [],
  });

  final String checkId;
  final String checkType;
  final ReleaseEvidenceCompatibilityStatus status;
  final String? expected;
  final String? actual;
  final List<String> reasons;
  final ReleaseEvidenceSourceReference? sourceReference;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'checkId': checkId,
        'checkType': checkType,
        'status': status.wireName,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
        if (reasons.isNotEmpty) 'reasons': reasons,
        if (sourceReference != null)
          'sourceReference': sourceReference!.toJson(),
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseEvidenceCompatibilityCheck.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseEvidenceCompatibilityCheck(
      checkId: json['checkId'] as String,
      checkType: json['checkType'] as String,
      status: ReleaseEvidenceCompatibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      expected: json['expected'] as String?,
      actual: json['actual'] as String?,
      reasons: List.unmodifiable(
        (json['reasons'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      sourceReference: json['sourceReference'] == null
          ? null
          : ReleaseEvidenceSourceReference.fromJson(
              json['sourceReference'] as Map<String, dynamic>,
            ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceCompatibilityCheck &&
          runtimeType == other.runtimeType &&
          checkId == other.checkId &&
          checkType == other.checkType &&
          status == other.status &&
          expected == other.expected &&
          actual == other.actual &&
          _listEquals(reasons, other.reasons) &&
          sourceReference == other.sourceReference &&
          _listEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        checkId,
        checkType,
        status,
        expected,
        actual,
        Object.hashAll(reasons),
        sourceReference,
        Object.hashAll(limitations),
      );
}

/// Compatibility assessment for a release evidence bundle.
class ReleaseEvidenceCompatibility {
  const ReleaseEvidenceCompatibility({
    required this.status,
    required this.checks,
    required this.compatibleSources,
    required this.partiallyCompatibleSources,
    required this.incompatibleSources,
    required this.unknownSources,
    required this.reasons,
    required this.compatibilityFingerprint,
  });

  final ReleaseEvidenceCompatibilityStatus status;
  final List<ReleaseEvidenceCompatibilityCheck> checks;
  final List<ReleaseEvidenceType> compatibleSources;
  final List<ReleaseEvidenceType> partiallyCompatibleSources;
  final List<ReleaseEvidenceType> incompatibleSources;
  final List<ReleaseEvidenceType> unknownSources;
  final List<String> reasons;
  final String compatibilityFingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'checks': checks.map((e) => e.toJson()).toList(),
        'compatibleSources': compatibleSources.map((e) => e.wireName).toList(),
        'partiallyCompatibleSources':
            partiallyCompatibleSources.map((e) => e.wireName).toList(),
        'incompatibleSources':
            incompatibleSources.map((e) => e.wireName).toList(),
        'unknownSources': unknownSources.map((e) => e.wireName).toList(),
        'reasons': reasons,
        'compatibilityFingerprint': compatibilityFingerprint,
      };

  factory ReleaseEvidenceCompatibility.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceCompatibility(
      status: ReleaseEvidenceCompatibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      checks: List.unmodifiable(
        (json['checks'] as List<dynamic>)
            .map(
              (e) => ReleaseEvidenceCompatibilityCheck.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      compatibleSources: List.unmodifiable(
        (json['compatibleSources'] as List<dynamic>)
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      partiallyCompatibleSources: List.unmodifiable(
        (json['partiallyCompatibleSources'] as List<dynamic>)
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      incompatibleSources: List.unmodifiable(
        (json['incompatibleSources'] as List<dynamic>)
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      unknownSources: List.unmodifiable(
        (json['unknownSources'] as List<dynamic>)
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      reasons: List.unmodifiable(
        (json['reasons'] as List<dynamic>).map((e) => e.toString()).toList(),
      ),
      compatibilityFingerprint: json['compatibilityFingerprint'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceCompatibility &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          _listEquals(checks, other.checks) &&
          _listEquals(compatibleSources, other.compatibleSources) &&
          _listEquals(
            partiallyCompatibleSources,
            other.partiallyCompatibleSources,
          ) &&
          _listEquals(incompatibleSources, other.incompatibleSources) &&
          _listEquals(unknownSources, other.unknownSources) &&
          _listEquals(reasons, other.reasons) &&
          compatibilityFingerprint == other.compatibilityFingerprint;

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(checks),
        Object.hashAll(compatibleSources),
        Object.hashAll(partiallyCompatibleSources),
        Object.hashAll(incompatibleSources),
        Object.hashAll(unknownSources),
        Object.hashAll(reasons),
        compatibilityFingerprint,
      );
}

/// Eligibility assessment for release evidence collection.
class ReleaseEvidenceEligibility {
  const ReleaseEvidenceEligibility({
    required this.status,
    required this.reasons,
    required this.missingSources,
    required this.incompatibleSources,
    required this.eligibilityFingerprint,
  });

  final ReleaseEvidenceEligibilityStatus status;
  final List<String> reasons;
  final List<ReleaseEvidenceType> missingSources;
  final List<ReleaseEvidenceType> incompatibleSources;
  final String eligibilityFingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'reasons': reasons,
        'missingSources': missingSources.map((e) => e.wireName).toList(),
        'incompatibleSources':
            incompatibleSources.map((e) => e.wireName).toList(),
        'eligibilityFingerprint': eligibilityFingerprint,
      };

  factory ReleaseEvidenceEligibility.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceEligibility(
      status: ReleaseEvidenceEligibilityStatusX.fromWireName(
        json['status'] as String,
      ),
      reasons: List.unmodifiable(
        (json['reasons'] as List<dynamic>).map((e) => e.toString()).toList(),
      ),
      missingSources: List.unmodifiable(
        (json['missingSources'] as List<dynamic>)
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      incompatibleSources: List.unmodifiable(
        (json['incompatibleSources'] as List<dynamic>)
            .map((e) => ReleaseEvidenceTypeX.fromWireName(e as String))
            .toList(),
      ),
      eligibilityFingerprint: json['eligibilityFingerprint'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceEligibility &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          _listEquals(reasons, other.reasons) &&
          _listEquals(missingSources, other.missingSources) &&
          _listEquals(incompatibleSources, other.incompatibleSources) &&
          eligibilityFingerprint == other.eligibilityFingerprint;

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(reasons),
        Object.hashAll(missingSources),
        Object.hashAll(incompatibleSources),
        eligibilityFingerprint,
      );
}

/// Coverage metrics for release evidence collection.
class ReleaseEvidenceCoverage {
  const ReleaseEvidenceCoverage({
    required this.requiredEvidenceCount,
    required this.presentEvidenceCount,
    required this.validEvidenceCount,
    required this.invalidEvidenceCount,
    required this.unavailableEvidenceCount,
    required this.incompatibleEvidenceCount,
    required this.expiredEvidenceCount,
    required this.normativeEvidenceCount,
    required this.supportingEvidenceCount,
    required this.requiredAttestationCount,
    required this.presentAttestationCount,
    required this.validAttestationCount,
    required this.invalidAttestationCount,
    required this.expiredAttestationCount,
    required this.unverifiedAttestationCount,
    required this.provenanceRequiredCount,
    required this.provenancePresentCount,
    required this.evidenceCoveragePercentage,
    required this.attestationCoveragePercentage,
    required this.provenanceCoveragePercentage,
    required this.sourceCoveragePercentage,
    required this.fingerprint,
  });

  final int requiredEvidenceCount;
  final int presentEvidenceCount;
  final int validEvidenceCount;
  final int invalidEvidenceCount;
  final int unavailableEvidenceCount;
  final int incompatibleEvidenceCount;
  final int expiredEvidenceCount;
  final int normativeEvidenceCount;
  final int supportingEvidenceCount;
  final int requiredAttestationCount;
  final int presentAttestationCount;
  final int validAttestationCount;
  final int invalidAttestationCount;
  final int expiredAttestationCount;
  final int unverifiedAttestationCount;
  final int provenanceRequiredCount;
  final int provenancePresentCount;
  final double evidenceCoveragePercentage;
  final double attestationCoveragePercentage;
  final double provenanceCoveragePercentage;
  final double sourceCoveragePercentage;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'requiredEvidenceCount': requiredEvidenceCount,
        'presentEvidenceCount': presentEvidenceCount,
        'validEvidenceCount': validEvidenceCount,
        'invalidEvidenceCount': invalidEvidenceCount,
        'unavailableEvidenceCount': unavailableEvidenceCount,
        'incompatibleEvidenceCount': incompatibleEvidenceCount,
        'expiredEvidenceCount': expiredEvidenceCount,
        'normativeEvidenceCount': normativeEvidenceCount,
        'supportingEvidenceCount': supportingEvidenceCount,
        'requiredAttestationCount': requiredAttestationCount,
        'presentAttestationCount': presentAttestationCount,
        'validAttestationCount': validAttestationCount,
        'invalidAttestationCount': invalidAttestationCount,
        'expiredAttestationCount': expiredAttestationCount,
        'unverifiedAttestationCount': unverifiedAttestationCount,
        'provenanceRequiredCount': provenanceRequiredCount,
        'provenancePresentCount': provenancePresentCount,
        'evidenceCoveragePercentage': evidenceCoveragePercentage,
        'attestationCoveragePercentage': attestationCoveragePercentage,
        'provenanceCoveragePercentage': provenanceCoveragePercentage,
        'sourceCoveragePercentage': sourceCoveragePercentage,
        'fingerprint': fingerprint,
      };

  factory ReleaseEvidenceCoverage.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceCoverage(
      requiredEvidenceCount: json['requiredEvidenceCount'] as int,
      presentEvidenceCount: json['presentEvidenceCount'] as int,
      validEvidenceCount: json['validEvidenceCount'] as int,
      invalidEvidenceCount: json['invalidEvidenceCount'] as int,
      unavailableEvidenceCount: json['unavailableEvidenceCount'] as int,
      incompatibleEvidenceCount: json['incompatibleEvidenceCount'] as int,
      expiredEvidenceCount: json['expiredEvidenceCount'] as int,
      normativeEvidenceCount: json['normativeEvidenceCount'] as int,
      supportingEvidenceCount: json['supportingEvidenceCount'] as int,
      requiredAttestationCount: json['requiredAttestationCount'] as int,
      presentAttestationCount: json['presentAttestationCount'] as int,
      validAttestationCount: json['validAttestationCount'] as int,
      invalidAttestationCount: json['invalidAttestationCount'] as int,
      expiredAttestationCount: json['expiredAttestationCount'] as int,
      unverifiedAttestationCount: json['unverifiedAttestationCount'] as int,
      provenanceRequiredCount: json['provenanceRequiredCount'] as int,
      provenancePresentCount: json['provenancePresentCount'] as int,
      evidenceCoveragePercentage:
          (json['evidenceCoveragePercentage'] as num).toDouble(),
      attestationCoveragePercentage:
          (json['attestationCoveragePercentage'] as num).toDouble(),
      provenanceCoveragePercentage:
          (json['provenanceCoveragePercentage'] as num).toDouble(),
      sourceCoveragePercentage:
          (json['sourceCoveragePercentage'] as num).toDouble(),
      fingerprint: json['fingerprint'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceCoverage &&
          runtimeType == other.runtimeType &&
          requiredEvidenceCount == other.requiredEvidenceCount &&
          presentEvidenceCount == other.presentEvidenceCount &&
          validEvidenceCount == other.validEvidenceCount &&
          invalidEvidenceCount == other.invalidEvidenceCount &&
          unavailableEvidenceCount == other.unavailableEvidenceCount &&
          incompatibleEvidenceCount == other.incompatibleEvidenceCount &&
          expiredEvidenceCount == other.expiredEvidenceCount &&
          normativeEvidenceCount == other.normativeEvidenceCount &&
          supportingEvidenceCount == other.supportingEvidenceCount &&
          requiredAttestationCount == other.requiredAttestationCount &&
          presentAttestationCount == other.presentAttestationCount &&
          validAttestationCount == other.validAttestationCount &&
          invalidAttestationCount == other.invalidAttestationCount &&
          expiredAttestationCount == other.expiredAttestationCount &&
          unverifiedAttestationCount == other.unverifiedAttestationCount &&
          provenanceRequiredCount == other.provenanceRequiredCount &&
          provenancePresentCount == other.provenancePresentCount &&
          evidenceCoveragePercentage == other.evidenceCoveragePercentage &&
          attestationCoveragePercentage ==
              other.attestationCoveragePercentage &&
          provenanceCoveragePercentage == other.provenanceCoveragePercentage &&
          sourceCoveragePercentage == other.sourceCoveragePercentage &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => Object.hashAll([
        requiredEvidenceCount,
        presentEvidenceCount,
        validEvidenceCount,
        invalidEvidenceCount,
        unavailableEvidenceCount,
        incompatibleEvidenceCount,
        expiredEvidenceCount,
        normativeEvidenceCount,
        supportingEvidenceCount,
        requiredAttestationCount,
        presentAttestationCount,
        validAttestationCount,
        invalidAttestationCount,
        expiredAttestationCount,
        unverifiedAttestationCount,
        provenanceRequiredCount,
        provenancePresentCount,
        evidenceCoveragePercentage,
        attestationCoveragePercentage,
        provenanceCoveragePercentage,
        sourceCoveragePercentage,
        fingerprint,
      ]);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
