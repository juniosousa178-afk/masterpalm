import 'package:flutter/material.dart';

import '../core/access_scope_service.dart';
import '../screens/metas_comissoes_screen.dart';
import '../screens/metas_comissoes_vendedor_screen.dart';
import 'acesso_admin_only_view.dart';

/// Gate de rota: não monta [child] (logo não agrega) se [allow] falhar.
class ScopeRouteGate extends StatefulWidget {
  const ScopeRouteGate({
    super.key,
    required this.allow,
    required this.child,
    this.deniedTitle = 'Disponível apenas para administradores',
    this.deniedSubtitle =
        'Este conteúdo consolida dados da loja e não é exibido ao vendedor.',
  });

  final bool Function(AccessScopeIdentity id) allow;
  final Widget child;
  final String deniedTitle;
  final String deniedSubtitle;

  @override
  State<ScopeRouteGate> createState() => _ScopeRouteGateState();
}

class _ScopeRouteGateState extends State<ScopeRouteGate> {
  AccessScopeIdentity? _id;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AccessScopeService.loadIdentity().then((id) {
      if (!mounted) return;
      setState(() {
        _id = id;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final id = _id;
    if (id == null || !widget.allow(id)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acesso')),
        body: AcessoAdminOnlyView(
          title: widget.deniedTitle,
          subtitle: widget.deniedSubtitle,
        ),
      );
    }
    return widget.child;
  }
}

/// Roteia Metas & Comissões admin × pessoal (fail-closed: sem admin implícito).
class MetasComissoesRoute extends StatelessWidget {
  const MetasComissoesRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccessScopeIdentity>(
      future: AccessScopeService.loadIdentity(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final id = snap.data!;
        if (id.isAdmin) {
          return const MetasComissoesScreen();
        }
        if (id.isSeller) {
          return const MetasComissoesVendedorScreen();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Acesso')),
          body: const AcessoAdminOnlyView(
            title: 'Perfil não identificado',
            subtitle:
                'Não foi possível confirmar o perfil. Faça login novamente.',
          ),
        );
      },
    );
  }
}
