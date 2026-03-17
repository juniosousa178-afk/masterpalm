import 'package:flutter/material.dart';

import '../widgets/dashboard_insights_section.dart';

class DashboardInsightsScreen extends StatelessWidget {
  final String lojaId;
  final bool isVendedor;
  final String? vendedorNome;

  const DashboardInsightsScreen({
    super.key,
    required this.lojaId,
    this.isVendedor = false,
    this.vendedorNome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestões', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: DashboardInsightsSection(
            lojaId: lojaId,
            isVendedor: isVendedor,
            vendedorNome: vendedorNome,
          ),
        ),
      ),
    );
  }
}

