// Rota inicial do MyApp no Web — pura, testável (R8.4.40).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

import '../catalog/catalog_initial_web_route.dart';

/// Resolve a rota inicial do [MyApp] no Web (`/login`, `/home`, …).
@visibleForTesting
String myAppWebInitialRoute({
  Uri? baseUri,
  bool? isWebOverride,
}) {
  final onWeb = isWebOverride ?? kIsWeb;
  if (!onWeb) return '/';
  final uri = baseUri ?? Uri.base;
  final path = uri.path.trim();
  if (path.isEmpty || path == '/') return '/';
  if (isAdminWebAppPath(uri)) return path;
  return '/';
}
