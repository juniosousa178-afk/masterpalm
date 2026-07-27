import 'release_supply_chain_enums.dart';
import 'release_supply_chain_equality.dart';

/// Compliance rule within a compliance policy.
class ComplianceRule {
  const ComplianceRule({
    required this.ruleId,
    required this.name,
    required this.severity,
    required this.expression,
    this.description,
    this.metadata = const {},
  });

  final String ruleId;
  final String name;
  final ComplianceRuleSeverity severity;
  final String expression;
  final String? description;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'name': name,
        'severity': severity.wireName,
        'expression': expression,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ComplianceRule.fromJson(Map<String, dynamic> json) {
    return ComplianceRule(
      ruleId: json['ruleId'] as String,
      name: json['name'] as String,
      severity:
          ComplianceRuleSeverityX.fromWireName(json['severity'] as String),
      expression: json['expression'] as String,
      description: json['description'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'ruleId': ruleId,
        'name': name,
        'severity': severity.wireName,
        'expression': expression,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ComplianceRule copyWith({
    String? ruleId,
    String? name,
    ComplianceRuleSeverity? severity,
    String? expression,
    String? description,
    Map<String, String>? metadata,
  }) {
    return ComplianceRule(
      ruleId: ruleId ?? this.ruleId,
      name: name ?? this.name,
      severity: severity ?? this.severity,
      expression: expression ?? this.expression,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplianceRule &&
          ruleId == other.ruleId &&
          name == other.name &&
          severity == other.severity &&
          expression == other.expression &&
          description == other.description &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        ruleId,
        name,
        severity,
        expression,
        description,
        Object.hashAll(metadata.entries),
      );
}

/// Compliance policy aggregating rules.
class CompliancePolicy {
  const CompliancePolicy({
    required this.policyId,
    required this.policyVersion,
    required this.name,
    required this.rules,
    this.limitations = const [],
  });

  final String policyId;
  final int policyVersion;
  final String name;
  final List<ComplianceRule> rules;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'rules': rules.map((e) => e.toJson()).toList(),
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory CompliancePolicy.fromJson(Map<String, dynamic> json) {
    return CompliancePolicy(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      name: json['name'] as String,
      rules: List.unmodifiable(
        (json['rules'] as List<dynamic>)
            .map((e) => ComplianceRule.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'name': name,
        'rules': (rules.map((e) => e.toComparableJson()).toList()
          ..sort((a, b) =>
              (a['ruleId'] as String).compareTo(b['ruleId'] as String))),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  CompliancePolicy copyWith({
    String? policyId,
    int? policyVersion,
    String? name,
    List<ComplianceRule>? rules,
    List<String>? limitations,
  }) {
    return CompliancePolicy(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      name: name ?? this.name,
      rules: rules ?? this.rules,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompliancePolicy &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          name == other.name &&
          rscListEquals(rules, other.rules) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        name,
        Object.hashAll(rules),
        Object.hashAll(limitations),
      );
}

/// Evidence supporting a compliance check.
class ComplianceEvidence {
  const ComplianceEvidence({
    required this.evidenceId,
    required this.evidenceType,
    required this.fingerprint,
    this.snapshotId,
    this.description,
    this.metadata = const {},
  });

  final String evidenceId;
  final String evidenceType;
  final String fingerprint;
  final String? snapshotId;
  final String? description;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'evidenceId': evidenceId,
        'evidenceType': evidenceType,
        if (snapshotId != null) 'snapshotId': snapshotId,
        'fingerprint': fingerprint,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ComplianceEvidence.fromJson(Map<String, dynamic> json) {
    return ComplianceEvidence(
      evidenceId: json['evidenceId'] as String,
      evidenceType: json['evidenceType'] as String,
      fingerprint: json['fingerprint'] as String,
      snapshotId: json['snapshotId'] as String?,
      description: json['description'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'evidenceId': evidenceId,
        'evidenceType': evidenceType,
        if (snapshotId != null) 'snapshotId': snapshotId,
        'fingerprint': fingerprint,
        if (description != null) 'description': description,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ComplianceEvidence copyWith({
    String? evidenceId,
    String? evidenceType,
    String? fingerprint,
    String? snapshotId,
    String? description,
    Map<String, String>? metadata,
  }) {
    return ComplianceEvidence(
      evidenceId: evidenceId ?? this.evidenceId,
      evidenceType: evidenceType ?? this.evidenceType,
      fingerprint: fingerprint ?? this.fingerprint,
      snapshotId: snapshotId ?? this.snapshotId,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplianceEvidence &&
          evidenceId == other.evidenceId &&
          evidenceType == other.evidenceType &&
          fingerprint == other.fingerprint &&
          snapshotId == other.snapshotId &&
          description == other.description &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        evidenceId,
        evidenceType,
        fingerprint,
        snapshotId,
        description,
        Object.hashAll(metadata.entries),
      );
}

/// Individual compliance check result.
class ComplianceCheck {
  const ComplianceCheck({
    required this.checkId,
    required this.ruleId,
    required this.status,
    required this.evidence,
    this.message,
    this.evaluatedAt,
  });

  final String checkId;
  final String ruleId;
  final ComplianceStatus status;
  final List<ComplianceEvidence> evidence;
  final String? message;
  final String? evaluatedAt;

  Map<String, dynamic> toJson() => {
        'checkId': checkId,
        'ruleId': ruleId,
        'status': status.wireName,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        if (message != null) 'message': message,
        if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
      };

  factory ComplianceCheck.fromJson(Map<String, dynamic> json) {
    return ComplianceCheck(
      checkId: json['checkId'] as String,
      ruleId: json['ruleId'] as String,
      status: ComplianceStatusX.fromWireName(json['status'] as String),
      evidence: List.unmodifiable(
        (json['evidence'] as List<dynamic>)
            .map(
              (e) => ComplianceEvidence.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
      message: json['message'] as String?,
      evaluatedAt: json['evaluatedAt'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'checkId': checkId,
        'ruleId': ruleId,
        'status': status.wireName,
        'evidence': (evidence.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) => (a['evidenceId'] as String)
                .compareTo(b['evidenceId'] as String),
          )),
        if (message != null) 'message': message,
      };

  ComplianceCheck copyWith({
    String? checkId,
    String? ruleId,
    ComplianceStatus? status,
    List<ComplianceEvidence>? evidence,
    String? message,
    String? evaluatedAt,
  }) {
    return ComplianceCheck(
      checkId: checkId ?? this.checkId,
      ruleId: ruleId ?? this.ruleId,
      status: status ?? this.status,
      evidence: evidence ?? this.evidence,
      message: message ?? this.message,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplianceCheck &&
          checkId == other.checkId &&
          ruleId == other.ruleId &&
          status == other.status &&
          rscListEquals(evidence, other.evidence) &&
          message == other.message &&
          evaluatedAt == other.evaluatedAt;

  @override
  int get hashCode => Object.hash(
        checkId,
        ruleId,
        status,
        Object.hashAll(evidence),
        message,
        evaluatedAt,
      );
}

/// Compliance violation detected during evaluation.
class ComplianceViolation {
  const ComplianceViolation({
    required this.violationId,
    required this.ruleId,
    required this.severity,
    required this.message,
    this.relatedId,
    this.metadata = const {},
  });

  final String violationId;
  final String ruleId;
  final ComplianceRuleSeverity severity;
  final String message;
  final String? relatedId;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'violationId': violationId,
        'ruleId': ruleId,
        'severity': severity.wireName,
        'message': message,
        if (relatedId != null) 'relatedId': relatedId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ComplianceViolation.fromJson(Map<String, dynamic> json) {
    return ComplianceViolation(
      violationId: json['violationId'] as String,
      ruleId: json['ruleId'] as String,
      severity:
          ComplianceRuleSeverityX.fromWireName(json['severity'] as String),
      message: json['message'] as String,
      relatedId: json['relatedId'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'violationId': violationId,
        'ruleId': ruleId,
        'severity': severity.wireName,
        'message': message,
        if (relatedId != null) 'relatedId': relatedId,
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  ComplianceViolation copyWith({
    String? violationId,
    String? ruleId,
    ComplianceRuleSeverity? severity,
    String? message,
    String? relatedId,
    Map<String, String>? metadata,
  }) {
    return ComplianceViolation(
      violationId: violationId ?? this.violationId,
      ruleId: ruleId ?? this.ruleId,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      relatedId: relatedId ?? this.relatedId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplianceViolation &&
          violationId == other.violationId &&
          ruleId == other.ruleId &&
          severity == other.severity &&
          message == other.message &&
          relatedId == other.relatedId &&
          rscMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        violationId,
        ruleId,
        severity,
        message,
        relatedId,
        Object.hashAll(metadata.entries),
      );
}

/// Compliance evaluation result for a release subject.
class ComplianceResult {
  const ComplianceResult({
    required this.resultId,
    required this.projectId,
    required this.status,
    required this.fingerprint,
    required this.policy,
    required this.checks,
    required this.violations,
    required this.schemaVersion,
    required this.evaluatedAt,
    this.releaseId,
    this.commitId,
    this.provenanceRecordId,
    this.supplyChainRecordId,
    this.sbomId,
    this.releaseEvidenceBundleId,
    this.warnings = const [],
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;

  final String resultId;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? provenanceRecordId;
  final String? supplyChainRecordId;
  final String? sbomId;
  final String? releaseEvidenceBundleId;
  final ComplianceStatus status;
  final String fingerprint;
  final CompliancePolicy policy;
  final List<ComplianceCheck> checks;
  final List<ComplianceViolation> violations;
  final int schemaVersion;
  final String evaluatedAt;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'resultId': resultId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (provenanceRecordId != null)
          'provenanceRecordId': provenanceRecordId,
        if (supplyChainRecordId != null)
          'supplyChainRecordId': supplyChainRecordId,
        if (sbomId != null) 'sbomId': sbomId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        'status': status.wireName,
        'fingerprint': fingerprint,
        'policy': policy.toJson(),
        'checks': checks.map((e) => e.toJson()).toList(),
        'violations': violations.map((e) => e.toJson()).toList(),
        'schemaVersion': schemaVersion,
        'evaluatedAt': evaluatedAt,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ComplianceResult.fromJson(Map<String, dynamic> json) {
    return ComplianceResult(
      resultId: json['resultId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      provenanceRecordId: json['provenanceRecordId'] as String?,
      supplyChainRecordId: json['supplyChainRecordId'] as String?,
      sbomId: json['sbomId'] as String?,
      releaseEvidenceBundleId: json['releaseEvidenceBundleId'] as String?,
      status: ComplianceStatusX.fromWireName(json['status'] as String),
      fingerprint: json['fingerprint'] as String,
      policy: CompliancePolicy.fromJson(json['policy'] as Map<String, dynamic>),
      checks: List.unmodifiable(
        (json['checks'] as List<dynamic>)
            .map((e) => ComplianceCheck.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      violations: List.unmodifiable(
        (json['violations'] as List<dynamic>)
            .map(
              (e) => ComplianceViolation.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      evaluatedAt: json['evaluatedAt'] as String,
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (provenanceRecordId != null)
          'provenanceRecordId': provenanceRecordId,
        if (supplyChainRecordId != null)
          'supplyChainRecordId': supplyChainRecordId,
        if (sbomId != null) 'sbomId': sbomId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        'status': status.wireName,
        'policy': policy.toComparableJson(),
        'checks': (checks.map((e) => e.toComparableJson()).toList()
          ..sort((a, b) =>
              (a['checkId'] as String).compareTo(b['checkId'] as String))),
        'violations': (violations.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) => (a['violationId'] as String)
                .compareTo(b['violationId'] as String),
          )),
        'schemaVersion': schemaVersion,
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ComplianceResult copyWith({
    String? resultId,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? provenanceRecordId,
    String? supplyChainRecordId,
    String? sbomId,
    String? releaseEvidenceBundleId,
    ComplianceStatus? status,
    String? fingerprint,
    CompliancePolicy? policy,
    List<ComplianceCheck>? checks,
    List<ComplianceViolation>? violations,
    int? schemaVersion,
    String? evaluatedAt,
    List<String>? warnings,
    List<String>? limitations,
  }) {
    return ComplianceResult(
      resultId: resultId ?? this.resultId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      provenanceRecordId: provenanceRecordId ?? this.provenanceRecordId,
      supplyChainRecordId: supplyChainRecordId ?? this.supplyChainRecordId,
      sbomId: sbomId ?? this.sbomId,
      releaseEvidenceBundleId:
          releaseEvidenceBundleId ?? this.releaseEvidenceBundleId,
      status: status ?? this.status,
      fingerprint: fingerprint ?? this.fingerprint,
      policy: policy ?? this.policy,
      checks: checks ?? this.checks,
      violations: violations ?? this.violations,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplianceResult &&
          resultId == other.resultId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          provenanceRecordId == other.provenanceRecordId &&
          supplyChainRecordId == other.supplyChainRecordId &&
          sbomId == other.sbomId &&
          releaseEvidenceBundleId == other.releaseEvidenceBundleId &&
          status == other.status &&
          fingerprint == other.fingerprint &&
          policy == other.policy &&
          rscListEquals(checks, other.checks) &&
          rscListEquals(violations, other.violations) &&
          schemaVersion == other.schemaVersion &&
          evaluatedAt == other.evaluatedAt &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        resultId,
        projectId,
        releaseId,
        commitId,
        provenanceRecordId,
        supplyChainRecordId,
        sbomId,
        releaseEvidenceBundleId,
        status,
        fingerprint,
        policy,
        Object.hashAll(checks),
        Object.hashAll(violations),
        schemaVersion,
        evaluatedAt,
        Object.hashAll(warnings),
        Object.hashAll(limitations),
      );
}
