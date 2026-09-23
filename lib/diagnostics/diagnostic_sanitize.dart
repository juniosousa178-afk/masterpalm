import 'dart:convert';

/// PII / secret redaction for diagnostic payloads.
/// Never log passwords, tokens, payment secrets, customer PII.

const List<String> kDiagnosticSecretKeyNeedles = [
  'password',
  'passwd',
  'secret',
  'token',
  'authtoken',
  'refreshtoken',
  'idtoken',
  'access_token',
  'apikey',
  'api_key',
  'authorization',
  'cookie',
  'session',
  'cpf',
  'cnpj',
  'rg',
  'telefone',
  'phone',
  'celular',
  'email',
  'endereco',
  'address',
  'cliente',
  'customer',
  'card',
  'cvv',
  'pan',
  'pagamento',
  'payment',
  'pix',
  'mp_access',
  'mercadopago',
];

const String kDiagnosticRedacted = '[REDACTED]';

bool isDiagnosticSensitiveKey(String key) {
  final n = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (final needle in kDiagnosticSecretKeyNeedles) {
    final nn = needle.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (n.contains(nn)) return true;
  }
  return false;
}

/// Hash-like stable mask for optional user id (not reversible identity).
String? hashUserIdForDiagnostic(String? uid) {
  if (uid == null || uid.trim().isEmpty) return null;
  final t = uid.trim();
  // Non-cryptographic short fingerprint — enough for correlation, not PII dump.
  var h = 0;
  for (final c in t.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final hex = h.toRadixString(16).padLeft(8, '0');
  return 'u_$hex';
}

dynamic sanitizeDiagnosticValue(dynamic raw, {int depth = 0}) {
  if (raw == null) return null;
  if (depth > 6) return '[TRUNCATED_DEPTH]';
  if (raw is String) {
    if (raw.length > 2000) return '${raw.substring(0, 2000)}…';
    // Heuristic: JWT-like or long opaque tokens
    if (raw.length > 40 && RegExp(r'^[A-Za-z0-9_\-\.]+$').hasMatch(raw)) {
      if (raw.contains('.') && raw.split('.').length >= 3) {
        return kDiagnosticRedacted;
      }
    }
    return raw;
  }
  if (raw is num || raw is bool) return raw;
  if (raw is List) {
    return raw
        .take(100)
        .map((e) => sanitizeDiagnosticValue(e, depth: depth + 1))
        .toList();
  }
  if (raw is Map) {
    return sanitizeDiagnosticMap(Map<String, dynamic>.from(raw), depth: depth);
  }
  return sanitizeDiagnosticValue(raw.toString(), depth: depth + 1);
}

Map<String, dynamic> sanitizeDiagnosticMap(
  Map<String, dynamic> raw, {
  int depth = 0,
}) {
  final out = <String, dynamic>{};
  for (final e in raw.entries) {
    final k = e.key.toString();
    if (isDiagnosticSensitiveKey(k)) {
      out[k] = kDiagnosticRedacted;
      continue;
    }
    out[k] = sanitizeDiagnosticValue(e.value, depth: depth + 1);
  }
  return out;
}

String? truncateStack(StackTrace? st, {int maxLines = 12}) {
  if (st == null) return null;
  final lines = st.toString().split('\n').where((l) => l.trim().isNotEmpty);
  return lines.take(maxLines).join('\n');
}

List<String> stackFramesList(StackTrace? st, {int maxLines = 12}) {
  if (st == null) return const [];
  return st
      .toString()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(maxLines)
      .toList();
}

String safeJsonEncode(Object? value) {
  return const JsonEncoder.withIndent('  ').convert(
    sanitizeDiagnosticValue(value),
  );
}
