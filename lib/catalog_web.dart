import 'package:flutter/material.dart';
import 'screens/public_catalog_screen.dart';

/// App de catálogo público (usado no Web)
class CatalogoApp extends StatelessWidget {
  const CatalogoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // URL atual: /loja/<slug>
    final uri = Uri.base;
    final segments = uri.pathSegments;

    // ✅ NUNCA usar 'masterpalm' como fallback: passaria loja errada.
    // Se URL não tiver /loja/slug, usar placeholder; o catálogo mostrará "Loja não encontrada".
    final slug = segments.length >= 2 && segments[0] == 'loja'
        ? segments[1]
        : 'minha-loja';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Loja $slug',
      theme: ThemeData.dark(),
      home: PublicCatalogScreen(
        lojaId: slug, // ✅ OBRIGATÓRIO AGORA
        preview: false, // mantém o catálogo em modo “cliente”
      ),
    );
  }
}
