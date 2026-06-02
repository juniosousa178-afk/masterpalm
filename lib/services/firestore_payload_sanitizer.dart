import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Resultado da sanitização de payload para escrita no Firestore.
class FirestorePayloadSanitizeResult {
  final Map<String, dynamic> payload;
  final List<String> adjustedPaths;

  const FirestorePayloadSanitizeResult({
    required this.payload,
    required this.adjustedPaths,
  });
}

/// Sanitização defensiva para garantir tipos aceitos pelo Firestore.
class FirestorePayloadSanitizer {
  FirestorePayloadSanitizer._();

  static FirestorePayloadSanitizeResult sanitizeMap(
    Map<String, dynamic> input, {
    String rootPath = 'payload',
  }) {
    final adjusted = <String>[];
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        throw FormatException('$rootPath: chave de mapa vazia');
      }
      final path = '$rootPath.$key';
      out[key] = _sanitizeValue(entry.value, path, adjusted);
    }
    return FirestorePayloadSanitizeResult(
      payload: out,
      adjustedPaths: adjusted,
    );
  }

  static dynamic _sanitizeValue(
    dynamic value,
    String path,
    List<String> adjusted,
  ) {
    if (value == null ||
        value is String ||
        value is bool ||
        value is Timestamp ||
        value is GeoPoint ||
        value is FieldValue ||
        value is Blob ||
        value is DocumentReference ||
        value is Uint8List) {
      return value;
    }

    if (value is num) {
      if (value.isFinite) return value;
      adjusted.add('$path: num não-finito -> 0');
      return 0;
    }

    if (value is DateTime) {
      return Timestamp.fromDate(value);
    }

    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key?.toString().trim() ?? '';
        if (key.isEmpty) {
          throw FormatException('$path: chave de mapa vazia');
        }
        out[key] = _sanitizeValue(entry.value, '$path.$key', adjusted);
      }
      return out;
    }

    if (value is Iterable) {
      final out = <dynamic>[];
      var i = 0;
      for (final e in value) {
        out.add(_sanitizeValue(e, '$path[$i]', adjusted));
        i++;
      }
      return out;
    }

    throw FormatException('$path: tipo não suportado (${value.runtimeType})');
  }
}
