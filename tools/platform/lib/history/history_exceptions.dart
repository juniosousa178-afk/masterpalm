import '../exceptions/platform_exception.dart';

/// History Engine specific errors.
class HistoryException extends PlatformException {
  HistoryException(super.message, {super.cause, super.code});
}

class HistoryConflictException extends HistoryException {
  HistoryConflictException(String snapshotId)
      : super(
          'History snapshot conflict for id: $snapshotId',
          code: 'history_conflict',
        );
}

class HistoryValidationException extends HistoryException {
  HistoryValidationException(String message)
      : super(message, code: 'history_validation_failed');
}

class HistoryNotFoundException extends HistoryException {
  HistoryNotFoundException(String snapshotId)
      : super('History snapshot not found: $snapshotId', code: 'not_found');
}
