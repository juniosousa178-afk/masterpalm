// lib/src/blob_fetch_stub.dart
// Stub para mobile/desktop - blob URLs não existem

import 'dart:typed_data';

/// Retorna null fora do web (blob URLs só existem no browser).
Future<Uint8List?> fetchBlobUrlAsBytes(String blobUrl) async => null;
