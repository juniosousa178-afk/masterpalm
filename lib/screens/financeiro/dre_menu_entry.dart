import 'package:flutter/material.dart';

/// Atalho visível da DRE. O texto não usa a cor primária do tema:
/// no tema claro ela é preta e desaparece no AppBar escuro de Relatórios.
class FinancialDreMenuTile extends StatelessWidget {
  const FinancialDreMenuTile({super.key, required this.onPressed});

  static const label = 'DRE — Demonstrativo de Resultado';

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: const Color(0xFF12121A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2A2A36)),
        ),
        child: InkWell(
          key: const Key('financial-dre-entry'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.assessment_outlined, color: Color(0xFF00A8FF)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
