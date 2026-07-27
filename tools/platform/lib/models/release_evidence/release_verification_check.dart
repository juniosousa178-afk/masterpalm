import 'release_evidence_enums.dart';

/// Individual verification check within a verification result.
class ReleaseVerificationCheck {
  const ReleaseVerificationCheck({
    required this.checkId,
    required this.checkType,
    required this.subjectId,
    required this.status,
    this.expected,
    this.actual,
    this.evidenceIds = const [],
    this.attestationIds = const [],
    this.explanation,
    this.fingerprint = '',
    this.limitations = const [],
  });

  final String checkId;
  final ReleaseVerificationCheckType checkType;
  final String subjectId;
  final String? expected;
  final String? actual;
  final ReleaseVerificationCheckStatus status;
  final List<String> evidenceIds;
  final List<String> attestationIds;
  final String? explanation;
  final String fingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'checkId': checkId,
        'checkType': checkType.wireName,
        'subjectId': subjectId,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
        'status': status.wireName,
        if (evidenceIds.isNotEmpty) 'evidenceIds': evidenceIds,
        if (attestationIds.isNotEmpty) 'attestationIds': attestationIds,
        if (explanation != null) 'explanation': explanation,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseVerificationCheck.fromJson(Map<String, dynamic> json) {
    return ReleaseVerificationCheck(
      checkId: json['checkId'] as String,
      checkType: ReleaseVerificationCheckTypeX.fromWireName(
        json['checkType'] as String,
      ),
      subjectId: json['subjectId'] as String,
      expected: json['expected'] as String?,
      actual: json['actual'] as String?,
      status: ReleaseVerificationCheckStatusX.fromWireName(
        json['status'] as String,
      ),
      evidenceIds: List.unmodifiable(
        (json['evidenceIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      attestationIds: List.unmodifiable(
        (json['attestationIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      explanation: json['explanation'] as String?,
      fingerprint: json['fingerprint'] as String? ?? '',
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
      other is ReleaseVerificationCheck &&
          runtimeType == other.runtimeType &&
          checkId == other.checkId &&
          checkType == other.checkType &&
          subjectId == other.subjectId &&
          expected == other.expected &&
          actual == other.actual &&
          status == other.status &&
          _listEquals(evidenceIds, other.evidenceIds) &&
          _listEquals(attestationIds, other.attestationIds) &&
          explanation == other.explanation &&
          fingerprint == other.fingerprint &&
          _listEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        checkId,
        checkType,
        subjectId,
        expected,
        actual,
        status,
        Object.hashAll(evidenceIds),
        Object.hashAll(attestationIds),
        explanation,
        fingerprint,
        Object.hashAll(limitations),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
