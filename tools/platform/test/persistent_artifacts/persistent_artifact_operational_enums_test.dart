import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('PersistentArtifactOperationalEnums', () {
    final cases = <String, (dynamic Function(String), String)>{
      'evaluationStatus': (
        PersistentArtifactEvaluationStatusX.fromWireName,
        'success',
      ),
      'sourceResolutionStatus': (
        PersistentArtifactSourceResolutionStatusX.fromWireName,
        'complete',
      ),
      'sourceResolutionMode': (
        PersistentArtifactSourceResolutionModeX.fromWireName,
        'latest',
      ),
      'sourceState': (PersistentArtifactSourceStateX.fromWireName, 'available'),
      'conflictType': (
        PersistentArtifactOperationalConflictTypeX.fromWireName,
        'fingerprintMismatch',
      ),
      'deletionDecision': (
        PersistentArtifactDeletionDecisionX.fromWireName,
        'allow',
      ),
      'requirementStatus': (
        PersistentArtifactRequirementStatusX.fromWireName,
        'satisfied',
      ),
    };

    for (final entry in cases.entries) {
      test('${entry.key} aceita wireName valido', () {
        final resolver = entry.value.$1;
        expect(() => resolver(entry.value.$2), returnsNormally);
      });
    }

    for (final entry in cases.entries) {
      test('${entry.key} rejeita wireName invalido', () {
        final resolver = entry.value.$1;
        expect(() => resolver('nao-existe'), throwsFormatException);
      });
    }
  });
}
