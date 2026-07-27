/// Base exception for all Platform Core errors.
class PlatformException implements Exception {
  PlatformException(this.message, {this.cause, this.code});

  final String message;
  final Object? cause;
  final String? code;

  @override
  String toString() {
    final buffer = StringBuffer('PlatformException: $message');
    if (code != null) buffer.write(' (code: $code)');
    if (cause != null) buffer.write(' — cause: $cause');
    return buffer.toString();
  }
}
