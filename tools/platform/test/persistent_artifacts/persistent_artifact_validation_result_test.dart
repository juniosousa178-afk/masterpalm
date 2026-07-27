import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_enums.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_validation_result.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('PersistentArtifactValidationResult', () {
    test('merge combines warnings errors and infos', () {
      final a = PersistentArtifactValidationResult(
        isValid: false,
        warnings: const ['warn-a'],
        errors: const ['err-a'],
        infos: const ['info-a'],
      );
      final b = PersistentArtifactValidationResult(
        isValid: false,
        warnings: const ['warn-b'],
        errors: const ['err-b'],
        infos: const ['info-b'],
      );
      final merged = PersistentArtifactValidationResult.merge([a, b]);
      expect(merged.warnings, containsAll(['warn-a', 'warn-b']));
      expect(merged.errors, containsAll(['err-a', 'err-b']));
      expect(merged.infos, containsAll(['info-a', 'info-b']));
    });

    test('merge deduplicates issues by code path and message', () {
      const issue = PersistentArtifactIssue(
        code: 'PA_DUP',
        path: 'field',
        severity: PersistentArtifactIssueSeverity.critical,
        message: 'duplicate issue',
      );
      final a = const PersistentArtifactValidationResult(
        isValid: false,
        issues: [issue],
        errors: const ['duplicate issue'],
      );
      final b = const PersistentArtifactValidationResult(
        isValid: false,
        issues: [issue],
        errors: const ['duplicate issue'],
      );
      final merged = PersistentArtifactValidationResult.merge([a, b]);
      expect(merged.issues, hasLength(1));
      expect(merged.errors, ['duplicate issue', 'duplicate issue']);
    });

    test('merge keeps distinct issues with different paths', () {
      final a = const PersistentArtifactValidationResult(
        isValid: false,
        issues: [
          PersistentArtifactIssue(
            code: 'PA_CODE',
            path: 'a',
            severity: PersistentArtifactIssueSeverity.critical,
            message: 'issue a',
          ),
        ],
        errors: const ['issue a'],
      );
      final b = const PersistentArtifactValidationResult(
        isValid: false,
        issues: [
          PersistentArtifactIssue(
            code: 'PA_CODE',
            path: 'b',
            severity: PersistentArtifactIssueSeverity.critical,
            message: 'issue b',
          ),
        ],
        errors: const ['issue b'],
      );
      final merged = PersistentArtifactValidationResult.merge([a, b]);
      expect(merged.issues, hasLength(2));
    });

    test('merge sorts issues by code', () {
      final result = PersistentArtifactValidationResult.merge([
        const PersistentArtifactValidationResult(
          isValid: false,
          issues: [
            PersistentArtifactIssue(
              code: 'PA_Z',
              path: 'z',
              severity: PersistentArtifactIssueSeverity.warning,
              message: 'z',
            ),
          ],
        ),
        const PersistentArtifactValidationResult(
          isValid: false,
          issues: [
            PersistentArtifactIssue(
              code: 'PA_A',
              path: 'a',
              severity: PersistentArtifactIssueSeverity.warning,
              message: 'a',
            ),
          ],
        ),
      ]);
      expect(result.issues.first.code, 'PA_A');
      expect(result.issues.last.code, 'PA_Z');
    });

    test('merge sorts warnings errors and infos', () {
      final merged = PersistentArtifactValidationResult.merge([
        const PersistentArtifactValidationResult(
          isValid: false,
          warnings: ['z-warn', 'a-warn'],
          errors: ['z-err', 'a-err'],
          infos: ['z-info', 'a-info'],
        ),
        const PersistentArtifactValidationResult(isValid: true),
      ]);
      expect(merged.warnings, ['a-warn', 'z-warn']);
      expect(merged.errors, ['a-err', 'z-err']);
      expect(merged.infos, ['a-info', 'z-info']);
    });

    test('merge isValid false when any errors present', () {
      final merged = PersistentArtifactValidationResult.merge([
        const PersistentArtifactValidationResult(isValid: true),
        const PersistentArtifactValidationResult(
          isValid: true,
          errors: ['blocking error'],
        ),
      ]);
      expect(merged.isValid, isFalse);
    });

    test('merge isValid true when all results have no errors', () {
      final merged = PersistentArtifactValidationResult.merge([
        const PersistentArtifactValidationResult(isValid: true),
        const PersistentArtifactValidationResult(
          isValid: false,
          warnings: const ['non-blocking'],
        ),
      ]);
      expect(merged.isValid, isTrue);
    });

    test('merge returns immutable issue list', () {
      final merged = PersistentArtifactValidationResult.merge([
        PersistentArtifactValidationResult(
          isValid: false,
          issues: [PersistentArtifactTestFixtures.validValidationIssue()],
        ),
      ]);
      expect(
        () => merged.issues
            .add(PersistentArtifactTestFixtures.validValidationIssue()),
        throwsUnsupportedError,
      );
    });

    test('copyWith preserves unmodified fields', () {
      final original = PersistentArtifactTestFixtures.validValidationResult();
      final copied = original.copyWith(isValid: true);
      expect(copied.isValid, isTrue);
      expect(copied.issues, equals(original.issues));
      expect(copied.warnings, equals(original.warnings));
    });

    test('equality considers issues warnings and errors', () {
      final a = PersistentArtifactTestFixtures.validValidationResult();
      final b = PersistentArtifactValidationResult.fromJson(a.toJson());
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
