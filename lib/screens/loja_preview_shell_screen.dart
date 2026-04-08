// Pré-visualização do catálogo (rascunho) com tier para subgates de pagamento/UI.
import 'package:flutter/material.dart';

import '../core/plan_access_resolver.dart';
import '../core/plan_matrix.dart';
import 'configure_loja_placeholder_screen.dart';
import 'public_catalog_screen.dart';

class LojaPreviewShellScreen extends StatelessWidget {
  const LojaPreviewShellScreen({super.key, required this.lojaId});

  final String lojaId;

  @override
  Widget build(BuildContext context) {
    if (lojaId.isEmpty) {
      return const ConfigureLojaPlaceholderScreen();
    }
    return FutureBuilder<PlanAccessTier>(
      future: PlanAccessResolver.currentTier(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final tier = snap.data ?? PlanAccessTier.freeLimited;
        return PublicCatalogScreen(
          lojaId: lojaId,
          preview: true,
          adminPreviewTier: tier,
        );
      },
    );
  }
}
