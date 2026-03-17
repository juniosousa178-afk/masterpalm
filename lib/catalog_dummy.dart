// lib/catalog_dummy.dart
import 'package:flutter/material.dart';

class CatalogApp extends StatelessWidget {
  const CatalogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text(
            'Catálogo só roda na Web. Abra /loja/<slug> no hosting.',
          ),
        ),
      ),
    );
  }
}
