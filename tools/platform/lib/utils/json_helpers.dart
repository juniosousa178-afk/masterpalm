import 'dart:convert';

/// JSON encoding and decoding helpers.
class JsonHelpers {
  const JsonHelpers();

  static dynamic decode(String source) => jsonDecode(source);

  static String encode(
    Object? value, {
    bool pretty = false,
  }) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return jsonEncode(value);
  }

  static Map<String, dynamic> asMap(Object? value, {String? label}) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException(
      label != null ? 'Expected map for $label' : 'Expected map',
    );
  }

  static List<dynamic> asList(Object? value, {String? label}) {
    if (value is List<dynamic>) return value;
    throw FormatException(
      label != null ? 'Expected list for $label' : 'Expected list',
    );
  }
}
