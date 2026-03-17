// lib/src/blob_fetch_web.dart
// Web: busca bytes de uma blob URL via fetch
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Busca bytes de uma blob URL (só funciona no browser que criou o blob).
Future<Uint8List?> fetchBlobUrlAsBytes(String blobUrl) async {
  try {
    final request = await html.HttpRequest.request(
      blobUrl,
      responseType: 'arraybuffer',
    );
    final buffer = request.response as ByteBuffer?;
    if (buffer == null) return null;
    return Uint8List.view(buffer);
  } catch (_) {
    return null;
  }
}
