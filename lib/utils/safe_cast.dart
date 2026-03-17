// lib/utils/safe_cast.dart
// Re-exporta helpers de parsing defensivo de core/safe_cast.
// Use para evitar TypeError (minified) com Firestore/RemoteConfig/Hive.

export '../core/safe_cast.dart' show
  asMap,
  asMapDeep,
  asList,
  asString,
  asNum,
  asBool,
  asDateTime,
  safeGet,
  castOrNull,
  mapFromDocData,
  mapStringDynamic,
  listOfMapStringDynamic,
  parseDate;
