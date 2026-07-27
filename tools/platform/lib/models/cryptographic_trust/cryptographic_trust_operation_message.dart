import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_operational_enums.dart';

/// Structured message surfaced during cryptographic trust evaluation.
class CryptographicTrustOperationMessage {
  const CryptographicTrustOperationMessage({
    required this.messageId,
    required this.code,
    required this.message,
    required this.severity,
    this.operation,
    this.sourceType,
    this.conflictType,
    this.metadata = const {},
  });

  final String messageId;
  final String code;
  final String message;
  final CryptographicIssueSeverity severity;
  final CryptographicTrustOperation? operation;
  final CryptographicSourceType? sourceType;
  final CryptographicTrustConflictType? conflictType;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'code': code,
        'message': message,
        'severity': severity.wireName,
        if (operation != null) 'operation': operation!.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (conflictType != null) 'conflictType': conflictType!.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustOperationMessage.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustOperationMessage(
      messageId: json['messageId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      severity: CryptographicIssueSeverityX.fromWireName(
        json['severity'] as String,
      ),
      operation: json['operation'] == null
          ? null
          : CryptographicTrustOperationX.fromWireName(
              json['operation'] as String,
            ),
      sourceType: json['sourceType'] == null
          ? null
          : CryptographicSourceTypeX.fromWireName(
              json['sourceType'] as String,
            ),
      conflictType: json['conflictType'] == null
          ? null
          : CryptographicTrustConflictTypeX.fromWireName(
              json['conflictType'] as String,
            ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'messageId': messageId,
        'code': code,
        'message': message,
        'severity': severity.wireName,
        if (operation != null) 'operation': operation!.wireName,
        if (sourceType != null) 'sourceType': sourceType!.wireName,
        if (conflictType != null) 'conflictType': conflictType!.wireName,
      };

  CryptographicTrustOperationMessage copyWith({
    String? messageId,
    String? code,
    String? message,
    CryptographicIssueSeverity? severity,
    CryptographicTrustOperation? operation,
    CryptographicSourceType? sourceType,
    CryptographicTrustConflictType? conflictType,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustOperationMessage(
      messageId: messageId ?? this.messageId,
      code: code ?? this.code,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      operation: operation ?? this.operation,
      sourceType: sourceType ?? this.sourceType,
      conflictType: conflictType ?? this.conflictType,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustOperationMessage &&
          messageId == other.messageId &&
          code == other.code &&
          message == other.message &&
          severity == other.severity &&
          operation == other.operation &&
          sourceType == other.sourceType &&
          conflictType == other.conflictType &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        messageId,
        code,
        message,
        severity,
        operation,
        sourceType,
        conflictType,
        Object.hashAll(metadata.entries),
      );
}
