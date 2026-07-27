import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_models.dart';

class PersistentArtifactCloudFingerprint {
  const PersistentArtifactCloudFingerprint._();

  static const String algorithm = 'sha256';

  static String fromComparableJson(Map<String, dynamic> comparable) {
    return sha256
        .convert(utf8.encode(jsonEncode(_normalize(comparable))))
        .toString();
  }

  static String backendDescriptor(
    PersistentArtifactCloudBackendDescriptor descriptor,
  ) {
    return fromComparableJson(descriptor.toComparableJson());
  }

  static String operationRequest(
      PersistentArtifactCloudOperationRequest request) {
    return fromComparableJson(request.toComparableJson());
  }

  static String operationResult(PersistentArtifactCloudOperationResult result) {
    return fromComparableJson(result.toComparableJson());
  }

  static String stagingDecision(
    PersistentArtifactCloudStagingReadinessDecision decision,
  ) {
    return fromComparableJson(decision.toComparableJson());
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    final keys = input.keys.toList()..sort();
    for (final key in keys) {
      output[key] = _normalizeValue(input[key]);
    }
    return output;
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _normalize(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    return value;
  }
}
