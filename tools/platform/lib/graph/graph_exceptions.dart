import '../exceptions/platform_exception.dart';

/// Graph Engine specific errors.
class GraphException extends PlatformException {
  GraphException(super.message, {super.cause, super.code});
}

class GraphParseException extends GraphException {
  GraphParseException(super.message, {super.cause, this.field});

  final String? field;
}
