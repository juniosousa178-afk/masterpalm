// lib/utils/image_provider.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Retorna um ImageProvider correto para:
///  - http/https  -> NetworkImage
///  - file:/// ou caminho absoluto -> FileImage (apenas mobile/desktop)
///  - fallback -> AssetImage (se quiser)
ImageProvider<Object> mpImageProvider(String? pathOrUrl,
    {ImageProvider<Object>? fallback}) {
  final String v = (pathOrUrl ?? '').trim();
  if (v.isEmpty) {
    return fallback ?? const AssetImage('assets/images/placeholder.png');
  }

  final lower = v.toLowerCase();
  final isHttp = lower.startsWith('http://') || lower.startsWith('https://');
  final isFileScheme = lower.startsWith('file://');
  final isAbsolutePath = v.startsWith('/'); // /data/user/0/... em Android
  // blob: no Web é ligado à origem; em localhost não carrega blob de app.mastepalm.com.br
  final isBlob = lower.startsWith('blob:');

  if (isHttp) {
    return NetworkImage(v);
  }

  if (kIsWeb && isBlob) {
    return fallback ?? const AssetImage('assets/images/placeholder.png');
  }

  if (!kIsWeb && (isFileScheme || isAbsolutePath)) {
    final path = isFileScheme ? Uri.parse(v).toFilePath() : v;
    return FileImage(File(path));
  }

  // Web não consegue ler caminho local -> usa fallback
  return fallback ?? const AssetImage('assets/images/placeholder.png');
}
