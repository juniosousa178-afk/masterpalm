import '../../models/persistent_artifacts/persistent_artifact_manifest.dart';
import '../../models/persistent_artifacts/persistent_artifact_query.dart';
import '../../models/persistent_artifacts/persistent_artifact_subject.dart';
import '../interfaces/persistent_artifact_content_handle.dart';
import 'persistent_artifact_physical_operation_status.dart';

class PersistentArtifactPhysicalIssue {
  const PersistentArtifactPhysicalIssue({
    required this.code,
    required this.message,
    this.metadata = const {},
  });

  final String code;
  final String message;
  final Map<String, String> metadata;
}

class PersistentArtifactPhysicalResult {
  const PersistentArtifactPhysicalResult({
    required this.status,
    this.issues = const [],
    this.metadata = const {},
  });

  final PersistentArtifactPhysicalOperationStatus status;
  final List<PersistentArtifactPhysicalIssue> issues;
  final Map<String, String> metadata;
}

class WritePhysicalContentRequest {
  const WritePhysicalContentRequest({
    required this.backendId,
    required this.contentId,
    required this.bytes,
    this.namespace,
  });

  final String backendId;
  final String contentId;
  final List<int> bytes;
  final String? namespace;
}

class WritePhysicalContentResult extends PersistentArtifactPhysicalResult {
  const WritePhysicalContentResult({
    required super.status,
    this.handle,
    this.digest,
    this.sizeBytes,
    this.idempotent = false,
    super.issues,
    super.metadata,
  });

  final PersistentArtifactContentHandle? handle;
  final String? digest;
  final int? sizeBytes;
  final bool idempotent;
}

class ReadPhysicalContentRequest {
  const ReadPhysicalContentRequest({
    required this.backendId,
    required this.handle,
  });

  final String backendId;
  final PersistentArtifactContentHandle handle;
}

class ReadPhysicalContentResult extends PersistentArtifactPhysicalResult {
  const ReadPhysicalContentResult({
    required super.status,
    this.bytes,
    this.digest,
    super.issues,
    super.metadata,
  });

  final List<int>? bytes;
  final String? digest;
}

class ContentExistsRequest {
  const ContentExistsRequest({
    required this.backendId,
    required this.handle,
  });

  final String backendId;
  final PersistentArtifactContentHandle handle;
}

class ContentExistsResult extends PersistentArtifactPhysicalResult {
  const ContentExistsResult({
    required super.status,
    required this.exists,
    super.issues,
    super.metadata,
  });

  final bool exists;
}

class ContentMetadataRequest {
  const ContentMetadataRequest({
    required this.backendId,
    required this.handle,
  });

  final String backendId;
  final PersistentArtifactContentHandle handle;
}

class ContentMetadataResult extends PersistentArtifactPhysicalResult {
  const ContentMetadataResult({
    required super.status,
    this.digest,
    this.sizeBytes,
    super.issues,
    super.metadata,
  });

  final String? digest;
  final int? sizeBytes;
}

class SavePhysicalManifestRequest {
  const SavePhysicalManifestRequest({
    required this.backendId,
    required this.manifest,
  });

  final String backendId;
  final PersistentArtifactManifest manifest;
}

class SavePhysicalManifestResult extends PersistentArtifactPhysicalResult {
  const SavePhysicalManifestResult({
    required super.status,
    required this.manifestId,
    this.idempotent = false,
    super.issues,
    super.metadata,
  });

  final String manifestId;
  final bool idempotent;
}

class LoadPhysicalManifestRequest {
  const LoadPhysicalManifestRequest({
    required this.backendId,
    required this.manifestId,
  });

  final String backendId;
  final String manifestId;
}

class LoadPhysicalManifestResult extends PersistentArtifactPhysicalResult {
  const LoadPhysicalManifestResult({
    required super.status,
    this.manifest,
    super.issues,
    super.metadata,
  });

  final PersistentArtifactManifest? manifest;
}

class LatestPhysicalManifestRequest {
  const LatestPhysicalManifestRequest({
    required this.backendId,
    required this.artifactId,
    this.namespace,
  });

  final String backendId;
  final String artifactId;
  final String? namespace;
}

class QueryPhysicalManifestsRequest {
  const QueryPhysicalManifestsRequest({
    required this.backendId,
    required this.query,
  });

  final String backendId;
  final PersistentArtifactQuery query;
}

class QueryPhysicalManifestsResult extends PersistentArtifactPhysicalResult {
  const QueryPhysicalManifestsResult({
    required super.status,
    this.manifests = const [],
    super.issues,
    super.metadata,
  });

  final List<PersistentArtifactManifest> manifests;
}

class InvalidatePhysicalManifestRequest {
  const InvalidatePhysicalManifestRequest({
    required this.backendId,
    required this.manifestId,
  });

  final String backendId;
  final String manifestId;
}

class ResolvePhysicalLocationRequest {
  const ResolvePhysicalLocationRequest({
    required this.backendId,
    required this.subject,
    this.useLatest = true,
  });

  final String backendId;
  final PersistentArtifactSubject subject;
  final bool useLatest;
}

class ResolvePhysicalLocationResult extends PersistentArtifactPhysicalResult {
  const ResolvePhysicalLocationResult({
    required super.status,
    this.locations = const [],
    super.issues,
    super.metadata,
  });

  final List<String> locations;
}

class QuarantineContentRequest {
  const QuarantineContentRequest({
    required this.backendId,
    required this.handle,
  });

  final String backendId;
  final PersistentArtifactContentHandle handle;
}

class QuarantineContentResult extends PersistentArtifactPhysicalResult {
  const QuarantineContentResult({
    required super.status,
    required this.quarantined,
    super.issues,
    super.metadata,
  });

  final bool quarantined;
}

class RecoveryObjectReference {
  const RecoveryObjectReference({
    required this.referenceId,
  });

  final String referenceId;
}

class RecoveryInspectionResult extends PersistentArtifactPhysicalResult {
  const RecoveryInspectionResult({
    required super.status,
    this.references = const [],
    super.issues,
    super.metadata,
  });

  final List<RecoveryObjectReference> references;
}

class RecoverTemporaryObjectRequest {
  const RecoverTemporaryObjectRequest({
    required this.backendId,
    required this.reference,
  });

  final String backendId;
  final String reference;
}

class DiscardTemporaryObjectRequest {
  const DiscardTemporaryObjectRequest({
    required this.backendId,
    required this.reference,
  });

  final String backendId;
  final String reference;
}

class UnregisterBackendRequest {
  const UnregisterBackendRequest({
    required this.backendId,
  });

  final String backendId;
}

extension PersistentArtifactPhysicalIssueJson
    on PersistentArtifactPhysicalIssue {
  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'metadata': metadata,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension PersistentArtifactPhysicalResultJson
    on PersistentArtifactPhysicalResult {
  Map<String, dynamic> toJson() => {
        'status': status.name,
        'issues': issues.map((it) => it.toJson()).toList(),
        'metadata': metadata,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension WritePhysicalContentRequestJson on WritePhysicalContentRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'contentId': contentId,
        'bytes': bytes,
        'namespace': namespace,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension WritePhysicalContentResultJson on WritePhysicalContentResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        // Handle is serialized as primitive fields to remain vendor-neutral.
        'handleId': handle?.handleId,
        'handleBackendId': handle?.backendId,
        'digest': digest,
        'sizeBytes': sizeBytes,
        'idempotent': idempotent,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension ReadPhysicalContentRequestJson on ReadPhysicalContentRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'handleId': handle.handleId,
        'handleBackendId': handle.backendId,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension ReadPhysicalContentResultJson on ReadPhysicalContentResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'bytes': bytes,
        'digest': digest,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension ContentExistsRequestJson on ContentExistsRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'handleId': handle.handleId,
        'handleBackendId': handle.backendId,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension ContentExistsResultJson on ContentExistsResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'exists': exists,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension ContentMetadataRequestJson on ContentMetadataRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'handleId': handle.handleId,
        'handleBackendId': handle.backendId,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension ContentMetadataResultJson on ContentMetadataResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'digest': digest,
        'sizeBytes': sizeBytes,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension SavePhysicalManifestRequestJson on SavePhysicalManifestRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'manifest': manifest.toJson(),
      };

  Map<String, dynamic> toComparableJson() => {
        'backendId': backendId,
        'manifest': manifest.toComparableJson(),
      };
}

extension SavePhysicalManifestResultJson on SavePhysicalManifestResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'manifestId': manifestId,
        'idempotent': idempotent,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension LoadPhysicalManifestRequestJson on LoadPhysicalManifestRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'manifestId': manifestId,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension LoadPhysicalManifestResultJson on LoadPhysicalManifestResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'manifest': manifest?.toJson(),
      };

  Map<String, dynamic> toComparableJson() => {
        ...(this as PersistentArtifactPhysicalResult).toComparableJson(),
        'manifest': manifest?.toComparableJson(),
      };
}

extension LatestPhysicalManifestRequestJson on LatestPhysicalManifestRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'artifactId': artifactId,
        'namespace': namespace,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension QueryPhysicalManifestsRequestJson on QueryPhysicalManifestsRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'query': query.toJson(),
      };

  Map<String, dynamic> toComparableJson() => {
        'backendId': backendId,
        'query': query.toComparableJson(),
      };
}

extension QueryPhysicalManifestsResultJson on QueryPhysicalManifestsResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'manifests': manifests.map((it) => it.toJson()).toList(),
      };

  Map<String, dynamic> toComparableJson() => {
        ...(this as PersistentArtifactPhysicalResult).toComparableJson(),
        'manifests': manifests.map((it) => it.toComparableJson()).toList(),
      };
}

extension InvalidatePhysicalManifestRequestJson
    on InvalidatePhysicalManifestRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'manifestId': manifestId,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension ResolvePhysicalLocationRequestJson on ResolvePhysicalLocationRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'subject': subject.toJson(),
        'useLatest': useLatest,
      };

  Map<String, dynamic> toComparableJson() => {
        'backendId': backendId,
        'subject': subject.toComparableJson(),
        'useLatest': useLatest,
      };
}

extension ResolvePhysicalLocationResultJson on ResolvePhysicalLocationResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'locations': locations,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension QuarantineContentRequestJson on QuarantineContentRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'handleId': handle.handleId,
        'handleBackendId': handle.backendId,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension QuarantineContentResultJson on QuarantineContentResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'quarantined': quarantined,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension RecoveryObjectReferenceJson on RecoveryObjectReference {
  Map<String, dynamic> toJson() => {'referenceId': referenceId};

  Map<String, dynamic> toComparableJson() => toJson();
}

extension RecoveryInspectionResultJson on RecoveryInspectionResult {
  Map<String, dynamic> toJson() => {
        ...(this as PersistentArtifactPhysicalResult).toJson(),
        'references': references.map((it) => it.toJson()).toList(),
      };

  Map<String, dynamic> toComparableJson() => {
        ...(this as PersistentArtifactPhysicalResult).toComparableJson(),
        'references': references.map((it) => it.toComparableJson()).toList(),
      };
}

extension RecoverTemporaryObjectRequestJson on RecoverTemporaryObjectRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'reference': reference,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension DiscardTemporaryObjectRequestJson on DiscardTemporaryObjectRequest {
  Map<String, dynamic> toJson() => {
        'backendId': backendId,
        'reference': reference,
      };

  Map<String, dynamic> toComparableJson() => toJson();
}

extension UnregisterBackendRequestJson on UnregisterBackendRequest {
  Map<String, dynamic> toJson() => {'backendId': backendId};

  Map<String, dynamic> toComparableJson() => toJson();
}

class PersistentArtifactPhysicalOperationJsonCodec {
  const PersistentArtifactPhysicalOperationJsonCodec._();

  static PersistentArtifactPhysicalIssue issueFromJson(
      Map<String, dynamic> json) {
    return PersistentArtifactPhysicalIssue(
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
      metadata: (json['metadata'] as Map?)?.map(
            (k, v) => MapEntry('$k', '$v'),
          ) ??
          const {},
    );
  }

  static PersistentArtifactPhysicalOperationStatus statusFromJson(
      String value) {
    return PersistentArtifactPhysicalOperationStatus.values.firstWhere(
      (it) => it.name == value,
      orElse: () => PersistentArtifactPhysicalOperationStatus.failed,
    );
  }

  static WritePhysicalContentRequest writeRequestFromJson(
    Map<String, dynamic> json,
  ) {
    return WritePhysicalContentRequest(
      backendId: json['backendId'] as String? ?? '',
      contentId: json['contentId'] as String? ?? '',
      bytes:
          (json['bytes'] as List?)?.map((it) => (it as num).toInt()).toList() ??
              const <int>[],
      namespace: json['namespace'] as String?,
    );
  }

  static ReadPhysicalContentRequest readRequestFromJson(
    Map<String, dynamic> json,
  ) {
    return ReadPhysicalContentRequest(
      backendId: json['backendId'] as String? ?? '',
      handle: InMemoryPersistentArtifactContentHandle(
        handleId: json['handleId'] as String? ?? '',
        backendId: json['handleBackendId'] as String? ?? '',
      ),
    );
  }

  static WritePhysicalContentResult writeResultFromJson(
    Map<String, dynamic> json,
  ) {
    return WritePhysicalContentResult(
      status: statusFromJson('${json['status'] ?? 'failed'}'),
      digest: json['digest'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      idempotent: json['idempotent'] == true,
      issues: _issuesFrom(json['issues']),
      metadata: _metadataFrom(json['metadata']),
    );
  }

  static ReadPhysicalContentResult readResultFromJson(
      Map<String, dynamic> json) {
    return ReadPhysicalContentResult(
      status: statusFromJson('${json['status'] ?? 'failed'}'),
      bytes:
          (json['bytes'] as List?)?.map((it) => (it as num).toInt()).toList(),
      digest: json['digest'] as String?,
      issues: _issuesFrom(json['issues']),
      metadata: _metadataFrom(json['metadata']),
    );
  }

  static ContentExistsResult existsResultFromJson(Map<String, dynamic> json) {
    return ContentExistsResult(
      status: statusFromJson('${json['status'] ?? 'failed'}'),
      exists: json['exists'] == true,
      issues: _issuesFrom(json['issues']),
      metadata: _metadataFrom(json['metadata']),
    );
  }

  static ContentMetadataResult metadataResultFromJson(
    Map<String, dynamic> json,
  ) {
    return ContentMetadataResult(
      status: statusFromJson('${json['status'] ?? 'failed'}'),
      digest: json['digest'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      issues: _issuesFrom(json['issues']),
      metadata: _metadataFrom(json['metadata']),
    );
  }

  static SavePhysicalManifestResult saveManifestResultFromJson(
    Map<String, dynamic> json,
  ) {
    return SavePhysicalManifestResult(
      status: statusFromJson('${json['status'] ?? 'failed'}'),
      manifestId: json['manifestId'] as String? ?? '',
      idempotent: json['idempotent'] == true,
      issues: _issuesFrom(json['issues']),
      metadata: _metadataFrom(json['metadata']),
    );
  }

  static List<PersistentArtifactPhysicalIssue> _issuesFrom(Object? source) {
    final list = source as List?;
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map((it) => issueFromJson(Map<String, dynamic>.from(it)))
        .toList();
  }

  static Map<String, String> _metadataFrom(Object? source) {
    final map = source as Map?;
    if (map == null) return const {};
    return map.map((k, v) => MapEntry('$k', '$v'));
  }
}
