// lib/screens/campanhas_sorteio_screen.dart
import 'package:flutter/material.dart';

import '../services/store_resolver_facade.dart';
import 'campanhas_sorteio_list_screen.dart';

class CampanhasSorteioScreen extends StatelessWidget {
  const CampanhasSorteioScreen({super.key});

  Future<String> _getLojaId() async {
    final id = await StoreResolverFacade.resolveForAdminApp();
    return (id ?? '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getLojaId(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final lojaId = snap.data!;
        if (lojaId.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Campanhas Sorteio')),
            body: const Center(
              child: Text('Selecione uma loja para acessar as campanhas.'),
            ),
          );
        }

        return CampanhasSorteioListScreen(lojaId: lojaId);
      },
    );
  }
}
