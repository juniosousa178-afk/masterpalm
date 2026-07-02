import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Erro fechado para valores fora do domínio JSON canônico V1.
class PdvV1CanonicalJsonError implements Exception {
  PdvV1CanonicalJsonError(this.message);

  final String message;

  @override
  String toString() => 'PdvV1CanonicalJsonError: $message';
}

/// Codifica [value] em JSON canônico determinístico (chaves de Map ordenadas).
String pdvV1CanonicalJsonEncode(Object? value) => _encodeValue(value);

/// SHA-256 hexadecimal minúsculo sobre UTF-8 de [canonicalJson].
String pdvV1Sha256HexUtf8(String canonicalJson) {
  final digest = sha256.convert(utf8.encode(canonicalJson));
  return digest.toString();
}

/// SHA-256 sobre a codificação canônica de [value].
String pdvV1CanonicalSha256(Object? value) =>
    pdvV1Sha256HexUtf8(pdvV1CanonicalJsonEncode(value));

String _encodeValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is int) {
    return value.toString();
  }
  if (value is double) {
    throw PdvV1CanonicalJsonError('double não suportado.');
  }
  if (value is num) {
    throw PdvV1CanonicalJsonError('num não-int não suportado.');
  }
  if (value is String) {
    return jsonEncode(value);
  }
  if (value is DateTime) {
    throw PdvV1CanonicalJsonError('DateTime não suportado.');
  }
  if (value is Set) {
    throw PdvV1CanonicalJsonError('Set não suportado.');
  }
  if (value.runtimeType.toString() == 'Uint8List') {
    throw PdvV1CanonicalJsonError('Uint8List não suportado.');
  }
  if (value is Function) {
    throw PdvV1CanonicalJsonError('Function não suportado.');
  }
  if (value is List) {
    final parts = <String>[];
    for (final element in value) {
      parts.add(_encodeValue(element));
    }
    return '[${parts.join(',')}]';
  }
  if (value is Map) {
    for (final key in value.keys) {
      if (key is! String) {
        throw PdvV1CanonicalJsonError('chave de Map deve ser String.');
      }
    }
    final keys = value.keys.cast<String>().toList()..sort();
    final parts = <String>[];
    for (final key in keys) {
      parts.add('${jsonEncode(key)}:${_encodeValue(value[key])}');
    }
    return '{${parts.join(',')}}';
  }
  throw PdvV1CanonicalJsonError(
    'tipo não suportado: ${value.runtimeType}',
  );
}
