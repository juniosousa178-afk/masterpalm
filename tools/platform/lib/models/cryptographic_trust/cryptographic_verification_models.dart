import 'cryptographic_attestation_models.dart';
import 'cryptographic_revocation_record.dart';
import 'cryptographic_signature_envelope.dart';
import 'cryptographic_transparency_log_reference.dart';
import 'cryptographic_trust_anchor.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_policy.dart';
import 'cryptographic_trust_subject.dart';

/// Structured issue from a cryptographic verification evaluation.
///
/// Verification success does not authorize release.
class CryptographicVerificationIssue {
  const CryptographicVerificationIssue({
    required this.code,
    required this.severity,
    required this.path,
    required this.message,
    this.subjectId,
    this.signatureId,
    this.attestationId,
    this.policyId,
    this.metadata = const {},
  });

  final String code;
  final CryptographicIssueSeverity severity;
  final String path;
  final String message;
  final String? subjectId;
  final String? signatureId;
  final String? attestationId;
  final String? policyId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'code': code,
        'severity': severity.wireName,
        'path': path,
        'message': message,
        if (subjectId != null) 'subjectId': subjectId,
        if (signatureId != null) 'signatureId': signatureId,
        if (attestationId != null) 'attestationId': attestationId,
        if (policyId != null) 'policyId': policyId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicVerificationIssue.fromJson(Map<String, dynamic> json) {
    return CryptographicVerificationIssue(
      code: json['code'] as String,
      severity: CryptographicIssueSeverityX.fromWireName(
        json['severity'] as String,
      ),
      path: json['path'] as String,
      message: json['message'] as String,
      subjectId: json['subjectId'] as String?,
      signatureId: json['signatureId'] as String?,
      attestationId: json['attestationId'] as String?,
      policyId: json['policyId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'code': code,
        'severity': severity.wireName,
        'path': path,
        'message': message,
        if (subjectId != null) 'subjectId': subjectId,
        if (signatureId != null) 'signatureId': signatureId,
        if (attestationId != null) 'attestationId': attestationId,
        if (policyId != null) 'policyId': policyId,
      };

  CryptographicVerificationIssue copyWith({
    String? code,
    CryptographicIssueSeverity? severity,
    String? path,
    String? message,
    String? subjectId,
    String? signatureId,
    String? attestationId,
    String? policyId,
    Map<String, String>? metadata,
  }) {
    return CryptographicVerificationIssue(
      code: code ?? this.code,
      severity: severity ?? this.severity,
      path: path ?? this.path,
      message: message ?? this.message,
      subjectId: subjectId ?? this.subjectId,
      signatureId: signatureId ?? this.signatureId,
      attestationId: attestationId ?? this.attestationId,
      policyId: policyId ?? this.policyId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicVerificationIssue &&
          code == other.code &&
          severity == other.severity &&
          path == other.path &&
          message == other.message &&
          subjectId == other.subjectId &&
          signatureId == other.signatureId &&
          attestationId == other.attestationId &&
          policyId == other.policyId &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        code,
        severity,
        path,
        message,
        subjectId,
        signatureId,
        attestationId,
        policyId,
        Object.hashAll(metadata.entries),
      );
}

/// Intent to perform future cryptographic verification — not executed in Part 1.
class CryptographicVerificationRequest {
  const CryptographicVerificationRequest({
    required this.requestId,
    required this.projectId,
    required this.subjects,
    required this.requestedAt,
    this.releaseId,
    this.signatures = const [],
    this.attestations = const [],
    this.policy,
    this.trustAnchors = const [],
    this.revocations = const [],
    this.transparencyLogReferences = const [],
    this.metadata = const {},
  });

  final String requestId;
  final String projectId;
  final String? releaseId;
  final List<CryptographicTrustSubject> subjects;
  final List<CryptographicSignatureEnvelope> signatures;
  final List<CryptographicAttestationStatement> attestations;
  final CryptographicTrustPolicy? policy;
  final List<CryptographicTrustAnchorReference> trustAnchors;
  final List<CryptographicRevocationRecord> revocations;
  final List<CryptographicTransparencyLogReference> transparencyLogReferences;
  final String requestedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'subjects': subjects.map((e) => e.toJson()).toList(),
        if (signatures.isNotEmpty)
          'signatures': signatures.map((e) => e.toJson()).toList(),
        if (attestations.isNotEmpty)
          'attestations': attestations.map((e) => e.toJson()).toList(),
        if (policy != null) 'policy': policy!.toJson(),
        if (trustAnchors.isNotEmpty)
          'trustAnchors': trustAnchors.map((e) => e.toJson()).toList(),
        if (revocations.isNotEmpty)
          'revocations': revocations.map((e) => e.toJson()).toList(),
        if (transparencyLogReferences.isNotEmpty)
          'transparencyLogReferences':
              transparencyLogReferences.map((e) => e.toJson()).toList(),
        'requestedAt': requestedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicVerificationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicVerificationRequest(
      requestId: json['requestId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      subjects: List.unmodifiable(
        (json['subjects'] as List<dynamic>)
            .map(
              (e) => CryptographicTrustSubject.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      signatures: List.unmodifiable(
        (json['signatures'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicSignatureEnvelope.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      attestations: List.unmodifiable(
        (json['attestations'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicAttestationStatement.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      policy: json['policy'] == null
          ? null
          : CryptographicTrustPolicy.fromJson(
              json['policy'] as Map<String, dynamic>,
            ),
      trustAnchors: List.unmodifiable(
        (json['trustAnchors'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustAnchorReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      revocations: List.unmodifiable(
        (json['revocations'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicRevocationRecord.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      transparencyLogReferences: List.unmodifiable(
        (json['transparencyLogReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTransparencyLogReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      requestedAt: json['requestedAt'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'requestId': requestId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'subjects': (subjects.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) =>
                a['subjectId'].toString().compareTo(b['subjectId'].toString()),
          )),
        if (signatures.isNotEmpty)
          'signatures': (signatures.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['signatureId']
                  .toString()
                  .compareTo(b['signatureId'].toString()),
            )),
        if (attestations.isNotEmpty)
          'attestations':
              (attestations.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['attestationId']
                      .toString()
                      .compareTo(b['attestationId'].toString()),
                )),
        if (policy != null) 'policy': policy!.toComparableJson(),
        if (trustAnchors.isNotEmpty)
          'trustAnchors':
              (trustAnchors.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['trustAnchorId']
                      .toString()
                      .compareTo(b['trustAnchorId'].toString()),
                )),
        if (revocations.isNotEmpty)
          'revocations': (revocations.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['revocationId']
                  .toString()
                  .compareTo(b['revocationId'].toString()),
            )),
        if (transparencyLogReferences.isNotEmpty)
          'transparencyLogReferences': (transparencyLogReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['entryId'].toString().compareTo(b['entryId'].toString()),
            )),
      };

  CryptographicVerificationRequest copyWith({
    String? requestId,
    String? projectId,
    String? releaseId,
    List<CryptographicTrustSubject>? subjects,
    List<CryptographicSignatureEnvelope>? signatures,
    List<CryptographicAttestationStatement>? attestations,
    CryptographicTrustPolicy? policy,
    List<CryptographicTrustAnchorReference>? trustAnchors,
    List<CryptographicRevocationRecord>? revocations,
    List<CryptographicTransparencyLogReference>? transparencyLogReferences,
    String? requestedAt,
    Map<String, String>? metadata,
  }) {
    return CryptographicVerificationRequest(
      requestId: requestId ?? this.requestId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      subjects: subjects ?? this.subjects,
      signatures: signatures ?? this.signatures,
      attestations: attestations ?? this.attestations,
      policy: policy ?? this.policy,
      trustAnchors: trustAnchors ?? this.trustAnchors,
      revocations: revocations ?? this.revocations,
      transparencyLogReferences:
          transparencyLogReferences ?? this.transparencyLogReferences,
      requestedAt: requestedAt ?? this.requestedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicVerificationRequest &&
          requestId == other.requestId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          trustListEquals(subjects, other.subjects) &&
          trustListEquals(signatures, other.signatures) &&
          trustListEquals(attestations, other.attestations) &&
          policy == other.policy &&
          trustListEquals(trustAnchors, other.trustAnchors) &&
          trustListEquals(revocations, other.revocations) &&
          trustListEquals(
            transparencyLogReferences,
            other.transparencyLogReferences,
          ) &&
          requestedAt == other.requestedAt &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        requestId,
        projectId,
        releaseId,
        Object.hashAll(subjects),
        Object.hashAll(signatures),
        Object.hashAll(attestations),
        policy,
        Object.hashAll(trustAnchors),
        Object.hashAll(revocations),
        Object.hashAll(transparencyLogReferences),
        requestedAt,
        Object.hashAll(metadata.entries),
      );
}

/// Per-subject verification outcome — declarative only.
class CryptographicSubjectVerificationResult {
  const CryptographicSubjectVerificationResult({
    required this.subjectId,
    required this.status,
    required this.trustLevel,
    this.issues = const [],
    this.metadata = const {},
  });

  final String subjectId;
  final CryptographicVerificationStatus status;
  final CryptographicTrustLevel trustLevel;
  final List<CryptographicVerificationIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicSubjectVerificationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicSubjectVerificationResult(
      subjectId: json['subjectId'] as String,
      status: CryptographicVerificationStatusX.fromWireName(
        json['status'] as String,
      ),
      trustLevel: CryptographicTrustLevelX.fromWireName(
        json['trustLevel'] as String,
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'subjectId': subjectId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['code'].toString().compareTo(b['code'].toString()),
            )),
      };

  CryptographicSubjectVerificationResult copyWith({
    String? subjectId,
    CryptographicVerificationStatus? status,
    CryptographicTrustLevel? trustLevel,
    List<CryptographicVerificationIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return CryptographicSubjectVerificationResult(
      subjectId: subjectId ?? this.subjectId,
      status: status ?? this.status,
      trustLevel: trustLevel ?? this.trustLevel,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicSubjectVerificationResult &&
          subjectId == other.subjectId &&
          status == other.status &&
          trustLevel == other.trustLevel &&
          trustListEquals(issues, other.issues) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        subjectId,
        status,
        trustLevel,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

/// Per-signature verification outcome — declarative only.
class CryptographicSignatureVerificationResult {
  const CryptographicSignatureVerificationResult({
    required this.signatureId,
    required this.status,
    required this.trustLevel,
    this.issues = const [],
    this.metadata = const {},
  });

  final String signatureId;
  final CryptographicVerificationStatus status;
  final CryptographicTrustLevel trustLevel;
  final List<CryptographicVerificationIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'signatureId': signatureId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicSignatureVerificationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicSignatureVerificationResult(
      signatureId: json['signatureId'] as String,
      status: CryptographicVerificationStatusX.fromWireName(
        json['status'] as String,
      ),
      trustLevel: CryptographicTrustLevelX.fromWireName(
        json['trustLevel'] as String,
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'signatureId': signatureId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['code'].toString().compareTo(b['code'].toString()),
            )),
      };

  CryptographicSignatureVerificationResult copyWith({
    String? signatureId,
    CryptographicVerificationStatus? status,
    CryptographicTrustLevel? trustLevel,
    List<CryptographicVerificationIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return CryptographicSignatureVerificationResult(
      signatureId: signatureId ?? this.signatureId,
      status: status ?? this.status,
      trustLevel: trustLevel ?? this.trustLevel,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicSignatureVerificationResult &&
          signatureId == other.signatureId &&
          status == other.status &&
          trustLevel == other.trustLevel &&
          trustListEquals(issues, other.issues) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        signatureId,
        status,
        trustLevel,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

/// Per-attestation verification outcome — declarative only.
class CryptographicAttestationVerificationResult {
  const CryptographicAttestationVerificationResult({
    required this.attestationId,
    required this.status,
    required this.trustLevel,
    this.issues = const [],
    this.metadata = const {},
  });

  final String attestationId;
  final CryptographicVerificationStatus status;
  final CryptographicTrustLevel trustLevel;
  final List<CryptographicVerificationIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'attestationId': attestationId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicAttestationVerificationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicAttestationVerificationResult(
      attestationId: json['attestationId'] as String,
      status: CryptographicVerificationStatusX.fromWireName(
        json['status'] as String,
      ),
      trustLevel: CryptographicTrustLevelX.fromWireName(
        json['trustLevel'] as String,
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'attestationId': attestationId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['code'].toString().compareTo(b['code'].toString()),
            )),
      };

  CryptographicAttestationVerificationResult copyWith({
    String? attestationId,
    CryptographicVerificationStatus? status,
    CryptographicTrustLevel? trustLevel,
    List<CryptographicVerificationIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return CryptographicAttestationVerificationResult(
      attestationId: attestationId ?? this.attestationId,
      status: status ?? this.status,
      trustLevel: trustLevel ?? this.trustLevel,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicAttestationVerificationResult &&
          attestationId == other.attestationId &&
          status == other.status &&
          trustLevel == other.trustLevel &&
          trustListEquals(issues, other.issues) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        attestationId,
        status,
        trustLevel,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

/// Per-policy verification outcome — declarative only.
class CryptographicPolicyVerificationResult {
  const CryptographicPolicyVerificationResult({
    required this.policyId,
    required this.status,
    required this.trustLevel,
    this.satisfiedRequirementIds = const [],
    this.issues = const [],
    this.metadata = const {},
  });

  final String policyId;
  final CryptographicVerificationStatus status;
  final CryptographicTrustLevel trustLevel;
  final List<String> satisfiedRequirementIds;
  final List<CryptographicVerificationIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (satisfiedRequirementIds.isNotEmpty)
          'satisfiedRequirementIds': satisfiedRequirementIds,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicPolicyVerificationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicPolicyVerificationResult(
      policyId: json['policyId'] as String,
      status: CryptographicVerificationStatusX.fromWireName(
        json['status'] as String,
      ),
      trustLevel: CryptographicTrustLevelX.fromWireName(
        json['trustLevel'] as String,
      ),
      satisfiedRequirementIds: List.unmodifiable(
        (json['satisfiedRequirementIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (satisfiedRequirementIds.isNotEmpty)
          'satisfiedRequirementIds': List<String>.from(satisfiedRequirementIds)
            ..sort(),
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['code'].toString().compareTo(b['code'].toString()),
            )),
      };

  CryptographicPolicyVerificationResult copyWith({
    String? policyId,
    CryptographicVerificationStatus? status,
    CryptographicTrustLevel? trustLevel,
    List<String>? satisfiedRequirementIds,
    List<CryptographicVerificationIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return CryptographicPolicyVerificationResult(
      policyId: policyId ?? this.policyId,
      status: status ?? this.status,
      trustLevel: trustLevel ?? this.trustLevel,
      satisfiedRequirementIds:
          satisfiedRequirementIds ?? this.satisfiedRequirementIds,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicPolicyVerificationResult &&
          policyId == other.policyId &&
          status == other.status &&
          trustLevel == other.trustLevel &&
          trustListEquals(
              satisfiedRequirementIds, other.satisfiedRequirementIds) &&
          trustListEquals(issues, other.issues) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        status,
        trustLevel,
        Object.hashAll(satisfiedRequirementIds),
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}

/// Aggregate cryptographic verification result — does not execute verification.
///
/// Status verified does not authorize release or deployment.
class CryptographicVerificationResult {
  const CryptographicVerificationResult({
    required this.verificationId,
    required this.requestId,
    required this.projectId,
    required this.status,
    required this.trustLevel,
    this.releaseId,
    this.subjectResults = const [],
    this.signatureResults = const [],
    this.attestationResults = const [],
    this.policyResults = const [],
    this.issues = const [],
    this.verifiedAt,
    this.metadata = const {},
  });

  final String verificationId;
  final String requestId;
  final String projectId;
  final String? releaseId;
  final CryptographicVerificationStatus status;
  final CryptographicTrustLevel trustLevel;
  final List<CryptographicSubjectVerificationResult> subjectResults;
  final List<CryptographicSignatureVerificationResult> signatureResults;
  final List<CryptographicAttestationVerificationResult> attestationResults;
  final List<CryptographicPolicyVerificationResult> policyResults;
  final List<CryptographicVerificationIssue> issues;
  final String? verifiedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'verificationId': verificationId,
        'requestId': requestId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (subjectResults.isNotEmpty)
          'subjectResults': subjectResults.map((e) => e.toJson()).toList(),
        if (signatureResults.isNotEmpty)
          'signatureResults': signatureResults.map((e) => e.toJson()).toList(),
        if (attestationResults.isNotEmpty)
          'attestationResults':
              attestationResults.map((e) => e.toJson()).toList(),
        if (policyResults.isNotEmpty)
          'policyResults': policyResults.map((e) => e.toJson()).toList(),
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (verifiedAt != null) 'verifiedAt': verifiedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicVerificationResult.fromJson(Map<String, dynamic> json) {
    return CryptographicVerificationResult(
      verificationId: json['verificationId'] as String,
      requestId: json['requestId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      status: CryptographicVerificationStatusX.fromWireName(
        json['status'] as String,
      ),
      trustLevel: CryptographicTrustLevelX.fromWireName(
        json['trustLevel'] as String,
      ),
      subjectResults: List.unmodifiable(
        (json['subjectResults'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicSubjectVerificationResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      signatureResults: List.unmodifiable(
        (json['signatureResults'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicSignatureVerificationResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      attestationResults: List.unmodifiable(
        (json['attestationResults'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicAttestationVerificationResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      policyResults: List.unmodifiable(
        (json['policyResults'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicPolicyVerificationResult.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationIssue.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      verifiedAt: json['verifiedAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'verificationId': verificationId,
        'requestId': requestId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'status': status.wireName,
        'trustLevel': trustLevel.wireName,
        if (subjectResults.isNotEmpty)
          'subjectResults':
              (subjectResults.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['subjectId']
                      .toString()
                      .compareTo(b['subjectId'].toString()),
                )),
        if (signatureResults.isNotEmpty)
          'signatureResults':
              (signatureResults.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['signatureId']
                      .toString()
                      .compareTo(b['signatureId'].toString()),
                )),
        if (attestationResults.isNotEmpty)
          'attestationResults':
              (attestationResults.map((e) => e.toComparableJson()).toList()
                ..sort(
                  (a, b) => a['attestationId']
                      .toString()
                      .compareTo(b['attestationId'].toString()),
                )),
        if (policyResults.isNotEmpty)
          'policyResults': (policyResults
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['policyId'].toString().compareTo(b['policyId'].toString()),
            )),
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['code'].toString().compareTo(b['code'].toString()),
            )),
      };

  CryptographicVerificationResult copyWith({
    String? verificationId,
    String? requestId,
    String? projectId,
    String? releaseId,
    CryptographicVerificationStatus? status,
    CryptographicTrustLevel? trustLevel,
    List<CryptographicSubjectVerificationResult>? subjectResults,
    List<CryptographicSignatureVerificationResult>? signatureResults,
    List<CryptographicAttestationVerificationResult>? attestationResults,
    List<CryptographicPolicyVerificationResult>? policyResults,
    List<CryptographicVerificationIssue>? issues,
    String? verifiedAt,
    Map<String, String>? metadata,
  }) {
    return CryptographicVerificationResult(
      verificationId: verificationId ?? this.verificationId,
      requestId: requestId ?? this.requestId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      status: status ?? this.status,
      trustLevel: trustLevel ?? this.trustLevel,
      subjectResults: subjectResults ?? this.subjectResults,
      signatureResults: signatureResults ?? this.signatureResults,
      attestationResults: attestationResults ?? this.attestationResults,
      policyResults: policyResults ?? this.policyResults,
      issues: issues ?? this.issues,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicVerificationResult &&
          verificationId == other.verificationId &&
          requestId == other.requestId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          status == other.status &&
          trustLevel == other.trustLevel &&
          trustListEquals(subjectResults, other.subjectResults) &&
          trustListEquals(signatureResults, other.signatureResults) &&
          trustListEquals(attestationResults, other.attestationResults) &&
          trustListEquals(policyResults, other.policyResults) &&
          trustListEquals(issues, other.issues) &&
          verifiedAt == other.verifiedAt &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        verificationId,
        requestId,
        projectId,
        releaseId,
        status,
        trustLevel,
        Object.hashAll(subjectResults),
        Object.hashAll(signatureResults),
        Object.hashAll(attestationResults),
        Object.hashAll(policyResults),
        Object.hashAll(issues),
        verifiedAt,
        Object.hashAll(metadata.entries),
      );
}
