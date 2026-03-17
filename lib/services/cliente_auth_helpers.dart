import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hashear senha com SHA256 (sem efeitos colaterais).
String hashSenha(String senha) {
  final bytes = utf8.encode(senha);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

/// Gerar ID único para cliente (baseado em timestamp atual).
String gerarClienteId() {
  return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond % 10000}';
}

/// Gerar portalToken aleatório e URL-safe.
String gerarPortalToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Formata Timestamp (ou objeto com .toDate()) em dd/MM/yyyy.
String formatarTimestamp(dynamic ts) {
  try {
    final dt = (ts as dynamic).toDate() as DateTime?;
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  } catch (_) {
    return '';
  }
}

