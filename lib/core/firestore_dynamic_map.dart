// Normalização de mapas vindos do Firestore / interop web (Map<String, Object?>).

import 'package:flutter/foundation.dart';

/// Mapa aninhado do Firestore sem cast direto para [Map<String, dynamic>].
/// Evita TypeError no web quando o runtime entrega [Map<String, Object?>].
Map<String, dynamic>? firestoreStringDynamicMapOrNull(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

Map<String, dynamic> firestoreStringDynamicMapOrEmpty(dynamic raw) =>
    firestoreStringDynamicMapOrNull(raw) ?? <String, dynamic>{};

/// Normalização recursiva para mapas aninhados (tam → cor → célula).
/// [firestoreStringDynamicMapOrEmpty] só normaliza o nível superior.
Map<String, dynamic> firestoreStringDynamicMapDeepOrEmpty(dynamic raw) {
  final top = firestoreStringDynamicMapOrEmpty(raw);
  final out = <String, dynamic>{};
  for (final e in top.entries) {
    final v = e.value;
    if (v is Map) {
      out[e.key] = firestoreStringDynamicMapDeepOrEmpty(v);
    } else {
      out[e.key] = v;
    }
  }
  return out;
}

/// Coerção segura de campos numéricos do Firestore (evita `as num?` no web).
int firestoreIntFieldOrZero(dynamic raw) {
  if (raw == null) return 0;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim()) ?? 0;
}

/// Reproduz o cast legado que falha no web com mapas [Map<String, Object?>].
@visibleForTesting
Map<String, dynamic>? legacyUnsafeFirestoreVariacoesCast(dynamic raw) =>
    raw as Map<String, dynamic>?;
