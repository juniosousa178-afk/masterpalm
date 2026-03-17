// lib/debug/global_error_hook.dart
// Tratamento global de erros: FlutterError, PlatformDispatcher, runZonedGuarded.
// Loga todos os erros com stack trace para facilitar debug (incl. AsyncError e minified).
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/logger.dart';

typedef GuardedMain = Future<void> Function();

/// Desempacota AsyncError para obter o erro real e stack trace.
void _logAsyncError(Object error, StackTrace stack) {
  Object unwrapped = error;
  StackTrace unwrappedStack = stack;
  if (error is AsyncError) {
    unwrapped = error.error;
    unwrappedStack = error.stackTrace;
  }
  logE('💥 [runZonedGuarded] $unwrapped', error: unwrapped, st: unwrappedStack);
}

Future<void> runWithGlobalErrorHook(GuardedMain body) async {
  // FlutterError.onError: erros síncronos durante build/layout (ex.: overflow, exception em widget)
  FlutterError.onError = (FlutterErrorDetails details) {
    logE('🔴 [FlutterError] ${details.exception}', error: details.exception, st: details.stack);
    FlutterError.presentError(details);
  };

  // PlatformDispatcher.onError: erros que escapam para o zone raiz (incl. assíncronos)
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    Object unwrapped = error;
    StackTrace unwrappedStack = stack;
    if (error is AsyncError) {
      unwrapped = error.error;
      unwrappedStack = error.stackTrace;
    }
    logE('💥 [PlatformDispatcher] $unwrapped', error: unwrapped, st: unwrappedStack);
    return true;
  };

  // ErrorWidget.builder: captura falhas no build de widgets (ex.: exceção em builder)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    logE('🟠 [ErrorWidget] ${details.exception}', error: details.exception, st: details.stack);
    return ErrorWidget(details.exception);
  };

  await runZonedGuarded(body, (error, stack) {
    Object unwrapped = error;
    if (error is AsyncError) {
      unwrapped = error.error;
    }
    final msg = unwrapped.toString();
    // AppCheck 400/throttled não deve ser tratado como fatal: apenas logar e seguir.
    if (msg.contains('AppCheck: 400') ||
        msg.toLowerCase().contains('throttled') ||
        (msg.contains('app-check') && msg.contains('400'))) {
      logD('[AppCheck] (ignorado) $unwrapped');
      return;
    }
    // TypeError de cast (ex.: catálogo) não derrubar como fatal; logar e seguir.
    if (msg.contains('TypeError') && msg.contains('subtype')) {
      logD('[CATALOGO] (ignorado) TypeError cast: $unwrapped');
      return;
    }
    _logAsyncError(error, stack);
  });
}
