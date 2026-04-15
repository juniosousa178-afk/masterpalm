import 'package:flutter/material.dart';

import '../core/plan_matrix.dart';
import '../core/plan_access_resolver.dart';

/// Bloqueia rota/tela premium quando o plano não permite (deep link, push, restauração).
class PlanGatedScreen extends StatefulWidget {
  const PlanGatedScreen({
    super.key,
    required this.feature,
    required this.child,
  });

  final PlanGateFeature feature;
  final Widget child;

  @override
  State<PlanGatedScreen> createState() => _PlanGatedScreenState();
}

class _PlanGatedScreenState extends State<PlanGatedScreen> {
  late final Future<bool> _allowed;

  @override
  void initState() {
    super.initState();
    _allowed = PlanAccessResolver.allows(widget.feature);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _allowed,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == true) {
          return widget.child;
        }
        return PlanBlockedScaffold(feature: widget.feature);
      },
    );
  }
}

class PlanBlockedScaffold extends StatelessWidget {
  const PlanBlockedScaffold({
    super.key,
    required this.feature,
  });

  final PlanGateFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurso do plano'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 56,
                  color: theme.colorScheme.primary.withOpacity(0.85),
                ),
                const SizedBox(height: 20),
                Text(
                  'Disponível em outro plano',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  PlanMatrix.upgradeHint(feature),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/planos');
                  },
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Ver planos e fazer upgrade'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
