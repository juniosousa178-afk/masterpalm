// lib/screens/public_catalog/widgets/catalog_section_title.dart
// Título de seção – extraído para reutilização no rodapé e outras partes.

import 'package:flutter/material.dart';

class CatalogSectionTitle extends StatelessWidget {
  final String text;
  final Color color;

  const CatalogSectionTitle(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: color,
        fontSize: 16,
      ),
      textAlign: TextAlign.center,
    );
  }
}
