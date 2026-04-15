// lib/widgets/public_header.dart
import 'package:flutter/material.dart';

class PublicHeader extends StatelessWidget {
  final String? logoUrl;
  final double logoAltura;
  final double logoLargura;
  final Color bg;
  final Color textColor;

  final TextEditingController searchController;
  final ValueChanged<String>? onSearchChanged;

  final List<String> categorias; // ex.: ['Todas', 'Camisetas', 'Calças'...]
  final String categoriaSelecionada;
  final ValueChanged<String> onCategoriaChanged;

  const PublicHeader({
    super.key,
    required this.logoUrl,
    required this.logoAltura,
    required this.logoLargura,
    required this.bg,
    required this.textColor,
    required this.searchController,
    required this.onSearchChanged,
    required this.categorias,
    required this.categoriaSelecionada,
    required this.onCategoriaChanged,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final logoW = logoLargura.clamp(0, w).toDouble();

    return Material(
      elevation: 2,
      color: bg,
      child: Column(
        children: [
          const SizedBox(height: 8),
          if ((logoUrl ?? '').trim().isNotEmpty)
            SizedBox(
              height: logoAltura,
              width: logoW,
              child: Image.network(
                logoUrl!.trim(),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar produto...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.black.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: categorias.map((c) {
                final selected = c == categoriaSelecionada;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c, overflow: TextOverflow.ellipsis),
                    selected: selected,
                    onSelected: (_) => onCategoriaChanged(c),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

