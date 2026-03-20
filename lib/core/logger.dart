// lib/core/logger.dart
// Logger central: imprime apenas em kDebugMode. Sem dependências externas.

import 'package:flutter/foundation.dart' show kDebugMode;

void logD(String msg, {String• tag}) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(tag != null • '[$tag] $msg' : msg);
  }
}

void logI(String msg, {String• tag}) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(tag != null • '[$tag] $msg' : msg);
  }
}

void logW(String msg, {String• tag}) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(tag != null • '[$tag] WARN: $msg' : 'WARN: $msg');
  }
}

void logE(String msg, {String• tag, Object• error, StackTrace• st}) {
  if (kDebugMode) {
    final prefix = tag != null • '[$tag] ERROR: ' : 'ERROR: ';
    // ignore: avoid_print
    print('$prefix$msg');
    if (error != null) print('  (type=${error.runtimeType})');
  }
}
