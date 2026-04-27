// lib/debug/global_error_hook.dart
// Tratamento global de erros: FlutterError, PlatformDispatcher, runZonedGuarded.
// Loga todos os erros com stack trace para facilitar debug (incl. AsyncError e minified).
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/logger.dart';
import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as plat;

typedef GuardedMain = Future<void> Function();
const String kCatalogDiagBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'dev',
);

/// Desempacota AsyncError para obter o erro real e stack trace.
void _logAsyncError(Object error, StackTrace stack) {
  Object unwrapped = error;
  StackTrace unwrappedStack = stack;
  if (error is AsyncError) {
    unwrapped = error.error;
    unwrappedStack = error.stackTrace;
  }
  logE('💥 [runZonedGuarded] $unwrapped', error: unwrapped, st: unwrappedStack);
  _logWebContext('runZonedGuarded');
}

void _logWebContext(String source) {
  if (!kIsWeb) return;
  try {
    final uri = Uri.base;
    final ua = plat.Web.userAgent();
    logD(
      '[WEB_CTX][$source] host=${uri.host} path=${uri.path} query=${uri.query} '
      'fragment=${uri.fragment} ua=$ua',
    );
  } catch (_) {}
}

Future<void> _persistWebRuntimeError(
  String source,
  Object error,
  StackTrace stack,
) async {
  if (!kIsWeb) return;
  try {
    final uri = Uri.base;
    String slug = '';
    if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'loja') {
      slug = uri.pathSegments[1].trim();
    }
    if (slug.isEmpty) {
      slug = (uri.queryParameters['loja'] ??
              uri.queryParameters['slug'] ??
              uri.queryParameters['store_id'] ??
              '')
          .trim();
    }
    final payload = <String, dynamic>{
      'buildId': kCatalogDiagBuildId,
      'timestamp': DateTime.now().toIso8601String(),
      'host': uri.host,
      'path': uri.path,
      'query': uri.query,
      'userAgent': plat.Web.userAgent(),
      'slug': slug,
      'lojaId': '',
      'error': error.toString(),
      'stack': stack.toString(),
      'fase': source,
      'phase': plat.Web.localStorageGet('mp_catalog_phase') ?? source,
      'appVersion': 'web',
    };
    plat.Web.localStorageSet('mp_last_runtime_error', jsonEncode(payload));
    if (Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('catalog_runtime_errors')
          .add(payload);
    }
  } catch (_) {}
}

Future<void> runWithGlobalErrorHook(GuardedMain body) async {
  // FlutterError.onError: erros síncronos durante build/layout (ex.: overflow, exception em widget)
  FlutterError.onError = (FlutterErrorDetails details) {
    logE('🔴 [FlutterError] ${details.exception}',
        error: details.exception, st: details.stack);
    _logWebContext('FlutterError.onError');
    unawaited(_persistWebRuntimeError(
      'render',
      details.exception,
      details.stack ?? StackTrace.current,
    ));
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
    logE('💥 [PlatformDispatcher] $unwrapped',
        error: unwrapped, st: unwrappedStack);
    _logWebContext('PlatformDispatcher.onError');
    unawaited(_persistWebRuntimeError(
      'platform_dispatcher',
      unwrapped,
      unwrappedStack,
    ));
    return true;
  };

  // ErrorWidget.builder: captura falhas no build de widgets (ex.: exceção em builder)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    logE('🟠 [ErrorWidget] ${details.exception}',
        error: details.exception, st: details.stack);
    unawaited(_persistWebRuntimeError(
      'error_widget',
      details.exception,
      details.stack ?? StackTrace.current,
    ));
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
      final st = (error is AsyncError) ? error.stackTrace : stack;
      unawaited(_persistWebRuntimeError('appcheck', unwrapped, st));
      return;
    }
    _logAsyncError(error, stack);
    final st = (error is AsyncError) ? error.stackTrace : stack;
    unawaited(_persistWebRuntimeError('run_zoned_guarded', unwrapped, st));
  });
}
