// lib/widgets/home_intelligent_section.dart
// Seção inteligente da home: Motor IA, Campanhas Sugeridas, Catálogo.
// Reutiliza MotorCrescimentoOrchestrator para badges. Sem cálculos novos complexos.

import 'package:flutter/material.dart';

import '../motor_crescimento/screens/motor_crescimento_screen.dart';
import '../motor_crescimento/services/motor_crescimento_orchestrator.dart';
import '../motor_crescimento_automacoes/screens/campanhas_sugeridas_screen.dart';
import '../screens/configure_loja_placeholder_screen.dart';
import '../screens/public_catalog_screen.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _warningColor = Color(0xFFF59E0B);
const Color _successColor = Color(0xFF22C55E);

/// Seção de atalhos inteligentes na home: Motor IA, Campanhas Sugeridas, Catálogo.
/// [lojaIdInterno] = contexto admin (Motor, Campanhas, Hive, Firestore).
/// [lojaSlugPublico] = identificador para link/catálogo público.
class HomeIntelligentSection extends StatelessWidget {
  final String lojaIdInterno;
  final String lojaSlugPublico;

  const HomeIntelligentSection({
    super.key,
    required this.lojaIdInterno,
    required this.lojaSlugPublico,
  });

  @override
  Widget build(BuildContext context) {
    if (lojaIdInterno.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<MotorCrescimentoPainel?>(
      future: MotorCrescimentoOrchestrator.carregarPainel(lojaIdInterno),
      builder: (context, snap) {
        final totalOportunidades = snap.hasData
            ? (snap.data!.totalProdutosParados + snap.data!.totalEstoqueBaixo)
            : 0;
        final temOportunidades = totalOportunidades > 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Text(
                  'Atalhos inteligentes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _IntelligentCard(
                      icon: Icons.rocket_launch_outlined,
                      label: 'Motor de Crescimento',
                      subtitle: 'Oportunidades e campanhas',
                      badge: temOportunidades ? totalOportunidades : null,
                      color: _primaryColor,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MotorCrescimentoScreen(lojaId: lojaIdInterno),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _IntelligentCard(
                      icon: Icons.auto_awesome_motion,
                      label: 'Campanhas',
                      subtitle: 'Ative com um clique',
                      badge: temOportunidades ? totalOportunidades : null,
                      color: _warningColor,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CampanhasSugeridasScreen(lojaId: lojaIdInterno),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _IntelligentCard(
                      icon: Icons.store_outlined,
                      label: 'Catálogo',
                      subtitle: 'Ver loja online',
                      badge: null,
                      color: _successColor,
                      onTap: () {
                        if (lojaSlugPublico.isEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ConfigureLojaPlaceholderScreen(),
                            ),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PublicCatalogScreen(lojaId: lojaSlugPublico),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IntelligentCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final int? badge;
  final Color color;
  final VoidCallback onTap;

  const _IntelligentCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.badge,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  if (badge != null && badge! > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
