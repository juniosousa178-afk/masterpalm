// Desembrulha erros do interop web (Future convertida / JSObject) para mensagem e retry.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Erro real após percorrer [error] / [cause] / encadeamento de "converted Future".
Object unwrapDartInteropError(Object e, {int maxDepth = 6}) {
  Object current = e;
  for (var depth = 0; depth < maxDepth; depth++) {
    final text = current.toString();
    if (!_pareceErroInteropGenerico(text)) {
      return current;
    }
    final inner = _lerErroEncadeado(current);
    if (inner == null || identical(inner, current)) break;
    current = inner;
  }
  return current;
}

/// Texto útil para UI/logs (Firebase code/message quando existir).
String formatDartErrorForUser(Object e) {
  final root = unwrapDartInteropError(e);
  if (root is FirebaseException) {
    final parts = <String>[
      if (root.message != null && root.message!.trim().isNotEmpty) root.message!.trim(),
      'code=${root.code}',
      if (root.plugin.isNotEmpty) 'plugin=${root.plugin}',
    ];
    return parts.join(' | ');
  }
  return root.toString();
}

/// Metadados seguros para log de diagnóstico (sem PII).
Map<String, String> dartErrorDiagMeta(Object e) {
  final root = unwrapDartInteropError(e);
  String? code;
  String? plugin;
  String? message;
  try {
    final dyn = root as dynamic;
    code = dyn.code?.toString();
    plugin = dyn.plugin?.toString();
    message = dyn.message?.toString();
  } catch (_) {}
  if (root is FirebaseException) {
    code ??= root.code;
    plugin ??= root.plugin;
    message ??= root.message;
  }
  return {
    'runtimeType': root.runtimeType.toString(),
    'outerRuntimeType': e.runtimeType.toString(),
    if (code != null && code.isNotEmpty) 'code': code,
    if (plugin != null && plugin.isNotEmpty) 'plugin': plugin,
    if (message != null && message.isNotEmpty) 'message': message,
    'unwrapped': formatDartErrorForUser(e),
  };
}

bool _pareceErroInteropGenerico(String text) {
  final lower = text.toLowerCase();
  return lower.contains('dart exception thrown from converted future') ||
      lower.contains('use the properties') && lower.contains("'error'");
}

Object? _lerErroEncadeado(Object e) {
  try {
    final dyn = e as dynamic;
    final err = dyn.error;
    if (err != null) return err as Object;
  } catch (_) {}
  try {
    final dyn = e as dynamic;
    final cause = dyn.cause;
    if (cause != null) return cause as Object;
  } catch (_) {}
  return null;
}
