import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/logger.dart';

/// Loga push/pop/replace/remove do [Navigator] no Web (correlaciona com histórico do browser).
class WebNavLogObserver extends NavigatorObserver {
  void _log(String action, Route<dynamic>? route, Route<dynamic>? other) {
    if (!kIsWeb) return;
    final n = route?.settings.name;
    final o = other?.settings.name;
    logD('[WEB_NAV] $action route.name=$n other.name=$o uri=${Uri.base}');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('didPush', route, previousRoute);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('didPop', route, previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _log('didReplace', newRoute, oldRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('didRemove', route, previousRoute);
    super.didRemove(route, previousRoute);
  }
}
