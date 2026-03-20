import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../services/admin_web_session_hydrator.dart';

/// No Web: aguarda [AdminWebSessionHydrator] antes de montar a tela admin (Vendas/Clientes).
/// No mobile: repassa o filho direto.
class AdminWebRouteShell extends StatefulWidget {
  final Widget child;

  const AdminWebRouteShell({super.key, required this.child});

  @override
  State<AdminWebRouteShell> createState() => _AdminWebRouteShellState();
}

class _AdminWebRouteShellState extends State<AdminWebRouteShell> {
  bool _ready = !kIsWeb;
  Object• _error;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      logD(
        '[WEB_NAV] AdminWebRouteShell initState uri=${Uri.base} → hydrate antes do filho',
      );
      _pump();
    }
  }

  Future<void> _pump() async {
    try {
      await AdminWebSessionHydrator.ensureHydrated();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Não foi possível preparar a sessão (web).\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}
