import '../exceptions/platform_exception.dart';

/// Score Engine specific errors.
class ScoreException extends PlatformException {
  ScoreException(super.message, {super.cause, super.code});
}

class ScoreConflictException extends ScoreException {
  ScoreConflictException(String snapshotId)
      : super(
          'Score snapshot conflict for id: $snapshotId',
          code: 'score_conflict',
        );
}

class ScoreValidationException extends ScoreException {
  ScoreValidationException(String message)
      : super(message, code: 'score_validation_failed');
}

class ScorePolicyException extends ScoreException {
  ScorePolicyException(String message)
      : super(message, code: 'score_policy_failed');
}

class ScoreNotFoundException extends ScoreException {
  ScoreNotFoundException(String snapshotId)
      : super('Score snapshot not found: $snapshotId', code: 'not_found');
}

class ScoreCompatibilityException extends ScoreException {
  ScoreCompatibilityException(String message)
      : super(message, code: 'score_incompatible');
}
