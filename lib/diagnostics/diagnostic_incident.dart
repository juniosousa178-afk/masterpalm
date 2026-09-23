import 'diagnostic_enums.dart';
import 'diagnostic_sanitize.dart';

/// Structured diagnostic incident — never contains secrets/PII when sanitized.
class DiagnosticIncident {
  DiagnosticIncident({
    required this.incidentId,
    required this.traceId,
    required this.storeId,
    required this.timestamp,
    required this.severity,
    required this.module,
    required this.operationType,
    required this.classification,
    required this.rootCauseStatus,
    required this.userTitle,
    required this.userMessage,
    required this.safeNextAction,
    this.userIdHash,
    this.technicalMessage,
    this.firebaseCode,
    this.httpCode,
    this.functionName,
    this.functionRevision,
    this.sourceOperationId,
    this.stockOperationId,
    this.productIds = const [],
    this.saleId,
    this.stage,
    this.stackFrames = const [],
    this.appVersion,
    this.gitCommit,
    this.buildId,
    this.networkState,
    this.online,
    Map<String, dynamic>? metadataSanitized,
  }) : metadataSanitized = sanitizeDiagnosticMap(metadataSanitized ?? const {});

  final String incidentId;
  final String traceId;
  final String storeId;
  final String? userIdHash;
  final DateTime timestamp;
  final DiagnosticSeverity severity;
  final DiagnosticModule module;
  final String operationType;
  final String classification;
  final DiagnosticRootCauseStatus rootCauseStatus;
  final String userTitle;
  final String userMessage;
  final String safeNextAction;
  final String? technicalMessage;
  final String? firebaseCode;
  final int? httpCode;
  final String? functionName;
  final String? functionRevision;
  final String? sourceOperationId;
  final String? stockOperationId;
  final List<String> productIds;
  final String? saleId;
  final String? stage;
  final List<String> stackFrames;
  final String? appVersion;
  final String? gitCommit;
  final String? buildId;
  final String? networkState;
  final bool? online;
  final Map<String, dynamic> metadataSanitized;

  Map<String, dynamic> toJson({bool includeStack = false}) => {
        'incidentId': incidentId,
        'traceId': traceId,
        'storeId': storeId,
        if (userIdHash != null) 'userIdHash': userIdHash,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'severity': severity.wire,
        'module': module.wire,
        'operationType': operationType,
        'classification': classification,
        'rootCauseStatus': rootCauseStatus.wire,
        'USER_TITLE': userTitle,
        'USER_MESSAGE': userMessage,
        'SAFE_NEXT_ACTION': safeNextAction,
        if (technicalMessage != null) 'technicalMessage': technicalMessage,
        if (firebaseCode != null) 'firebaseCode': firebaseCode,
        if (httpCode != null) 'httpCode': httpCode,
        if (functionName != null) 'functionName': functionName,
        if (functionRevision != null) 'functionRevision': functionRevision,
        if (sourceOperationId != null) 'sourceOperationId': sourceOperationId,
        if (stockOperationId != null) 'stockOperationId': stockOperationId,
        if (productIds.isNotEmpty) 'productIds': productIds,
        if (saleId != null) 'saleId': saleId,
        if (stage != null) 'stage': stage,
        if (includeStack && stackFrames.isNotEmpty) 'stackFrames': stackFrames,
        if (appVersion != null) 'appVersion': appVersion,
        if (gitCommit != null) 'gitCommit': gitCommit,
        if (buildId != null) 'buildId': buildId,
        if (networkState != null) 'networkState': networkState,
        if (online != null) 'online': online,
        'metadataSanitized': metadataSanitized,
      };

  factory DiagnosticIncident.fromJson(Map<String, dynamic> json) {
    return DiagnosticIncident(
      incidentId: (json['incidentId'] ?? '').toString(),
      traceId: (json['traceId'] ?? '').toString(),
      storeId: (json['storeId'] ?? '').toString(),
      userIdHash: json['userIdHash']?.toString(),
      timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString())?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      severity: DiagnosticSeverity.parse(json['severity']?.toString()),
      module: DiagnosticModule.parse(json['module']?.toString()),
      operationType: (json['operationType'] ?? '').toString(),
      classification: (json['classification'] ?? DiagnosticClassification.unknownError)
          .toString(),
      rootCauseStatus:
          DiagnosticRootCauseStatus.parse(json['rootCauseStatus']?.toString()),
      userTitle: (json['USER_TITLE'] ?? json['userTitle'] ?? '').toString(),
      userMessage: (json['USER_MESSAGE'] ?? json['userMessage'] ?? '').toString(),
      safeNextAction:
          (json['SAFE_NEXT_ACTION'] ?? json['safeNextAction'] ?? '').toString(),
      technicalMessage: json['technicalMessage']?.toString(),
      firebaseCode: json['firebaseCode']?.toString(),
      httpCode: json['httpCode'] is int
          ? json['httpCode'] as int
          : int.tryParse('${json['httpCode'] ?? ''}'),
      functionName: json['functionName']?.toString(),
      functionRevision: json['functionRevision']?.toString(),
      sourceOperationId: json['sourceOperationId']?.toString(),
      stockOperationId: json['stockOperationId']?.toString(),
      productIds: (json['productIds'] is List)
          ? (json['productIds'] as List).map((e) => e.toString()).toList()
          : const [],
      saleId: json['saleId']?.toString(),
      stage: json['stage']?.toString(),
      stackFrames: (json['stackFrames'] is List)
          ? (json['stackFrames'] as List).map((e) => e.toString()).toList()
          : const [],
      appVersion: json['appVersion']?.toString(),
      gitCommit: json['gitCommit']?.toString(),
      buildId: json['buildId']?.toString(),
      networkState: json['networkState']?.toString(),
      online: json['online'] is bool ? json['online'] as bool : null,
      metadataSanitized: json['metadataSanitized'] is Map
          ? Map<String, dynamic>.from(json['metadataSanitized'] as Map)
          : const {},
    );
  }
}
