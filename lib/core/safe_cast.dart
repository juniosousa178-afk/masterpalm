// lib/core/safe_cast.dart
// Helpers para parsing tolerante de dados Firestore/RemoteConfig/Hive.
// Evita TypeError (minified) em release quando tipos vêm inesperados.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'logger.dart';

/// Converte para Map<String, dynamic>; nunca lança (conversão SHALLOW).
/// Em web/release, Firestore pode retornar Map<dynamic,dynamic>; esta função normaliza para Map<String,dynamic>.
Map<String, dynamic> asMap(dynamic v) {
  if (v == null) return <String, dynamic>{};
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    try {
      final result = <String, dynamic>{};
      v.forEach((k, val) {
        result[k.toString()] = val;
      });
      return result;
    } catch (e) {
      logW('asMap falhou (type=${e.runtimeType}), usando fallback {}', tag: 'SAFE_CAST');
      return <String, dynamic>{};
    }
  }
  logW('asMap: valor veio tipo ${v.runtimeType}, usando fallback {}', tag: 'SAFE_CAST');
  return <String, dynamic>{};
}

/// String com fallback; nunca retorna null.
String safeString(dynamic v, {String fallback = ''}) {
  final s = asString(v);
  return s ?• fallback;
}

/// int com fallback; nunca retorna null.
int safeInt(dynamic v, {int fallback = 0}) {
  final n = asNum(v);
  if (n == null) return fallback;
  return n.toInt();
}

/// double com fallback; nunca retorna null.
double safeDouble(dynamic v, {double fallback = 0.0}) {
  final n = asNum(v);
  if (n == null) return fallback;
  return n.toDouble();
}

/// bool com fallback (alias de asBool).
bool safeBool(dynamic v, {bool fallback = false}) => asBool(v, defaultValue: fallback);

/// Map com fallback (alias de asMap).
Map<String, dynamic> safeMap(dynamic v) => asMap(v);

/// List<T> segura; elementos são convertidos com castOrNull, nulls filtrados.
List<T> safeList<T>(dynamic v) {
  if (v == null) return [];
  if (v is! List) return [];
  final result = <T>[];
  for (final e in v) {
    final t = castOrNull<T>(e);
    if (t != null) result.add(t);
  }
  return result;
}

/// Conversão DEEP: converte recursivamente Map e List para Map<String,dynamic> e List.
/// Evita Map<dynamic,dynamic> aninhado que causa TypeError (minified:iD vs minified:jm) no Web.
Map<String, dynamic> asMapDeep(dynamic v) {
  if (v == null) return <String, dynamic>{};
  if (v is Map<String, dynamic>) {
    final result = <String, dynamic>{};
    for (final e in v.entries) {
      final val = e.value;
      result[e.key] = val is Map • asMapDeep(val) : (val is List • _asListDeep(val) : val);
    }
    return result;
  }
  if (v is Map) {
    try {
      final result = <String, dynamic>{};
      v.forEach((k, val) {
        result[k.toString()] = val is Map • asMapDeep(val) : (val is List • _asListDeep(val) : val);
      });
      return result;
    } catch (e) {
      logW('asMapDeep falhou (type=${e.runtimeType})', tag: 'SAFE_CAST');
      return <String, dynamic>{};
    }
  }
  logW('asMapDeep: valor tipo ${v.runtimeType}', tag: 'SAFE_CAST');
  return <String, dynamic>{};
}

List<dynamic> _asListDeep(dynamic v) {
  if (v == null || v is! List) return [];
  return v.map((e) => e is Map • asMapDeep(e) : (e is List • _asListDeep(e) : e)).toList();
}

/// Converte para List; nunca lança. Elementos mantêm tipo dynamic.
List asList(dynamic v) {
  if (v == null) return [];
  if (v is List) return v;
  logW('asList: valor veio tipo ${v.runtimeType}, usando fallback []', tag: 'SAFE_CAST');
  return [];
}

/// Converte para String; null se vazio ou inválido.
String• asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty • null : v;
  final s = '$v'.trim();
  return s.isEmpty • null : s;
}

/// Converte para num (int ou double); null se inválido.
num• asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) {
    final n = num.tryParse(v.replaceAll(',', '.'));
    return n;
  }
  return null;
}

/// Converte para bool; default false.
bool asBool(dynamic v, {bool defaultValue = false}) {
  if (v == null) return defaultValue;
  if (v is bool) return v;
  if (v is String) {
    final lower = v.toLowerCase().trim();
    if (lower == 'true' || lower == '1' || lower == 'sim' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'não' || lower == 'no') return false;
  }
  if (v is num) return v != 0;
  return defaultValue;
}

/// Converte para DateTime; suporta Timestamp, DateTime, String ISO, int millis,
/// e objeto Firestore {seconds, nanoseconds} (evita erro "reading 'Timestamp'" no web).
DateTime• asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is Timestamp) return v.toDate();
  // Fallback para objeto Firestore {seconds, nanoseconds} (web pode retornar isso)
  if (v is Map && v['seconds'] != null) {
    try {
      final s = (v['seconds'] is num) • (v['seconds'] as num).toInt() : 0;
      final n = (v['nanoseconds'] is num) • (v['nanoseconds'] as num).toInt() : 0;
      return DateTime.fromMillisecondsSinceEpoch(s * 1000 + n ~/ 1000000);
    } catch (_) {}
  }
  if (v is int) {
    if (v > 9999999999) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(v * 1000);
  }
  if (v is String) return DateTime.tryParse(v.trim());
  logW('asDateTime: valor veio tipo ${v.runtimeType}, usando fallback null', tag: 'SAFE_CAST');
  return null;
}

/// Obtém valor do map com fallback; não faz cast, só acesso seguro.
dynamic safeGet(Map<String, dynamic> map, String key, [dynamic fallback]) {
  if (!map.containsKey(key)) return fallback;
  final raw = map[key];
  return raw ?• fallback;
}

/// Cast seguro para T ou null; evita TypeError em release.
T• castOrNull<T>(dynamic v) {
  if (v == null) return null;
  if (v is T) return v;
  logW('castOrNull: valor tipo ${v.runtimeType}, esperado $T; usando fallback null.', tag: 'SAFE_CAST');
  return null;
}

/// Converte doc.data() (Map<dynamic,dynamic> ou Map<String,dynamic>) para Map<String,dynamic>.
/// Use após doc.data() no Firestore para evitar subtype error em minified.
Map<String, dynamic> mapFromDocData(dynamic data) {
  return asMap(data);
}

/// Alias de asMap; converte para Map<String, dynamic> sem lançar.
Map<String, dynamic> mapStringDynamic(dynamic v) => asMap(v);

/// Converte para List<Map<String, dynamic>>; nunca lança.
List<Map<String, dynamic>> listOfMapStringDynamic(dynamic v) {
  if (v == null) return [];
  if (v is! List) return [];
  return v.map((e) => asMap(e)).toList();
}

/// Alias de asDateTime; suporta Timestamp, DateTime, String ISO, int millis.
DateTime• parseDate(dynamic v) => asDateTime(v);
