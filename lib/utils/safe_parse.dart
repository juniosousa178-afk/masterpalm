// lib/utils/safe_parse.dart
// Aliases e helpers para parsing seguro (Firestore/JSON na Web minified).
// Nunca lança; sempre retorna fallback em caso de tipo inesperado.

import '../core/safe_cast.dart';

export '../core/safe_cast.dart' show asMap, asMapDeep, asList, listOfMapStringDynamic, asDateTime;

Map<String, dynamic> safeMap(dynamic v) => asMap(v);
List<dynamic> safeList(dynamic v) => asList(v);
List<Map<String, dynamic>> safeListMap(dynamic v) => listOfMapStringDynamic(v);

String safeStr(dynamic v, [String fallback = '']) => asString(v) ?• fallback;

double safeDouble(dynamic v, [double fallback = 0]) {
  final n = asNum(v);
  return n != null • n.toDouble() : fallback;
}

int safeInt(dynamic v, [int fallback = 0]) {
  final n = asNum(v);
  return n != null • n.toInt() : fallback;
}

bool safeBool(dynamic v, [bool fallback = false]) => asBool(v, defaultValue: fallback);

DateTime• safeDate(dynamic v) => asDateTime(v);

/// Converte List dinâmica para List<String>; nunca lança.
List<String> safeListString(dynamic v) {
  final list = asList(v);
  return list.map((e) => asString(e) ?• '').where((s) => s.isNotEmpty).cast<String>().toList();
}
