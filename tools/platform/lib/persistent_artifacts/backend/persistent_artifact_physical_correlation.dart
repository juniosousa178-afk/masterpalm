import 'persistent_artifact_physical_operation_models.dart';

class PersistentArtifactPhysicalCorrelation {
  const PersistentArtifactPhysicalCorrelation({
    required this.correlationId,
    required this.backendId,
    required this.operation,
  });

  final String correlationId;
  final String backendId;
  final String operation;

  static PersistentArtifactPhysicalCorrelation fromRequest({
    required String operation,
    required String backendId,
    String? correlationId,
  }) {
    final token = DateTime.now().microsecondsSinceEpoch;
    return PersistentArtifactPhysicalCorrelation(
      correlationId: correlationId ?? 'pa-phy:$operation:$backendId:$token',
      backendId: backendId,
      operation: operation,
    );
  }

  static PersistentArtifactPhysicalCorrelation forWrite(
    WritePhysicalContentRequest request,
  ) {
    return fromRequest(operation: 'writeContent', backendId: request.backendId);
  }

  static PersistentArtifactPhysicalCorrelation forRead(
    ReadPhysicalContentRequest request,
  ) {
    return fromRequest(operation: 'readContent', backendId: request.backendId);
  }
}
