import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint utilities for release supply chain domain models.
///
/// Not an engine — pure serialization helper for domain Part 1.
class ReleaseSupplyChainFingerprint {
  const ReleaseSupplyChainFingerprint._();

  static const String algorithm = 'sha256';

  static String fromComparableJson(Map<String, dynamic> comparable) {
    return sha256
        .convert(utf8.encode(jsonEncode(_normalize(comparable))))
        .toString();
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    final keys = input.keys.toList()..sort();
    for (final key in keys) {
      output[key] = _normalizeValue(input[key]);
    }
    return output;
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _normalize(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    return value;
  }
}
