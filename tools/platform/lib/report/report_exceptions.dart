import '../exceptions/platform_exception.dart';

/// Report Engine specific errors.
class ReportException extends PlatformException {
  ReportException(super.message, {super.cause, super.code});
}

class ReportSourceException extends ReportException {
  ReportSourceException(
    super.message, {
    super.cause,
    this.sourceKind,
  });

  final String? sourceKind;
}
