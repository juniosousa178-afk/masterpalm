import 'platform_exception.dart';

/// Raised when an analysis operation fails.
class AnalysisException extends PlatformException {
  AnalysisException(
    super.message, {
    super.cause,
    super.code,
    this.context,
  });

  final String? context;

  @override
  String toString() {
    final base = super.toString();
    if (context != null) return '$base [context: $context]';
    return base;
  }
}
