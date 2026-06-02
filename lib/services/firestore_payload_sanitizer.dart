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

  /// `FieldValue.delete()` cria instância nova a cada chamada — usar [==], não [identical].
  static bool isDeleteFieldValue(dynamic value) {
    return value is FieldValue && value == FieldValue.delete();
  }

  /// Remove sentinels `deleteField()` de payload para `set()` sem `merge: true`.
  static Map<String, dynamic> stripDeleteSentinelsForFullSet(
    Map<String, dynamic> input, {
    String rootPath = 'payload',
    List<String>? removedPaths,
  }) {
    final removed = removedPaths ?? <String>[];
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      final path = '$rootPath.$key';
      final value = entry.value;
      if (isDeleteFieldValue(value)) {
        removed.add(path);
        continue;
      }
      if (value is Map) {
        final nested = stripDeleteSentinelsForFullSet(
          Map<String, dynamic>.from(value),
          rootPath: path,
          removedPaths: removed,
        );
        if (nested.isNotEmpty) {
          out[key] = nested;
        }
        continue;
      }
      out[key] = value;
    }
    return out;
  }

  static FirestorePayloadSanitizeResult sanitizeMap(
    Map<String, dynamic> input, {
    String rootPath = 'payload',
    bool forFullDocumentSet = false,
  }) {
    final adjusted = <String>[];
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        throw FormatException('$rootPath: chave de mapa vazia');
      }
      final path = '$rootPath.$key';
      if (forFullDocumentSet && isDeleteFieldValue(entry.value)) {
        adjusted.add('$path: deleteField removido (set sem merge)');
        continue;
      }
      out[key] = _sanitizeValue(
        entry.value,
        path,
        adjusted,
        forFullDocumentSet: forFullDocumentSet,
      );
    }
    return FirestorePayloadSanitizeResult(
      payload: out,
      adjustedPaths: adjusted,
    );
  }

  static dynamic _sanitizeValue(
    dynamic value,
    String path,
    List<String> adjusted, {
    bool forFullDocumentSet = false,
  }) {
    if (forFullDocumentSet && isDeleteFieldValue(value)) {
      adjusted.add('$path: deleteField removido (set sem merge)');
      return null;
    }
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
        out[key] = _sanitizeValue(
          entry.value,
          '$path.$key',
          adjusted,
          forFullDocumentSet: forFullDocumentSet,
        );
      }
      return out;
    }

    if (value is Iterable) {
      final out = <dynamic>[];
      var i = 0;
      for (final e in value) {
        out.add(_sanitizeValue(
          e,
          '$path[$i]',
          adjusted,
          forFullDocumentSet: forFullDocumentSet,
        ));
        i++;
      }
      return out;
    }

    throw FormatException('$path: tipo não suportado (${value.runtimeType})');
  }
}
