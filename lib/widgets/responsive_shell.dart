// lib/widgets/responsive_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/responsive.dart';

/// Shell responsivo: sidebar fixa em desktop, nada em mobile (usa Drawer normal).
/// Usado no HomeScreen para layout web adaptado.
class ResponsiveShell extends StatelessWidget {
  final Widget body;
  final Widget? sidebar;
  final Color sidebarColor;

  const ResponsiveShell({
    super.key,
    required this.body,
    this.sidebar,
    this.sidebarColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    // Mobile: só retorna o body (drawer ? controlado pelo Scaffold)
    if (!kIsWeb || isMobile(context) || sidebar == null) {
      return body;
    }

    // Desktop/Tablet web: sidebar fixa + conteúdo (usa tema para modo escuro)
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final effectiveSidebarColor = sidebarColor == Colors.white ? surfaceColor : sidebarColor;

    return Row(
      children: [
        // Sidebar fixa
        SizedBox(
          width: 280,
          child: Material(
            color: effectiveSidebarColor,
            elevation: 2,
            child: sidebar!,
          ),
        ),
        // Conteúdo principal
        Expanded(child: body),
      ],
    );
  }
}

/// Widget para sidebar do admin - lista de menu com scroll
class AdminSidebar extends StatelessWidget {
  final String usuario;
  final String tipo;
  final List<Widget> menuItems;
  final VoidCallback onLogout;

  static const Color _primaryColor = Color(0xFF6366F1);

  const AdminSidebar({
    super.key,
    required this.usuario,
    required this.tipo,
    required this.menuItems,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header do sidebar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, size: 28, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                usuario,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tipo.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Menu items com scroll
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: menuItems,
          ),
        ),
      ],
    );
  }
}

