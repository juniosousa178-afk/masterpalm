// lib/widgets/dashboard_home_cards.dart
// Cards de resumo na home: vendas hoje, estoque baixo, meta do mês. Sempre por lojaId.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../core/hive_box_names.dart';
import '../core/access_scope_service.dart';
import '../core/venda_metrics_filter.dart';
import '../models/produto.dart';
import '../utils/store_access_guard.dart';
import '../models/venda.dart';
import '../models/meta.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _warningColor = Color(0xFFF59E0B);

/// Dashboard com 3 cards: Vendas hoje, Produtos com estoque baixo, Meta do mês.
/// [lojaId] obrigatório – dados sempre da loja atual.
class DashboardHomeCards extends StatelessWidget {
  final String lojaId;

  const DashboardHomeCards({super.key, required this.lojaId});

  @override
  Widget build(BuildContext context) {
    if (lojaId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<Map<String, dynamic>>(
      future: _loadDashboardData(lojaId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          return const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator(color: _primaryColor)),
          );
        }
        final d = snap.data!;
        final vendasHoje = d['vendasHoje'] as double;
        final qtdEstoqueBaixo = d['qtdEstoqueBaixo'] as int;
        final metaAtual = d['metaAtual'] as double;
        final metaAtingida = d['metaAtingida'] as double;
        final isSeller = d['isSeller'] as bool? ?? false;

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: _DashboardCard(
                  icon: Icons.point_of_sale,
                  label: isSeller ? 'Minhas vendas' : 'Vendas hoje',
                  value: 'R\$ ${vendasHoje.toStringAsFixed(2).replaceAll('.', ',')}',
                  color: _successColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DashboardCard(
                  icon: Icons.inventory_2_outlined,
                  label: 'Estoque baixo',
                  value: '$qtdEstoqueBaixo',
                  color: qtdEstoqueBaixo > 0 ? _warningColor : _primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DashboardCard(
                  icon: Icons.flag_outlined,
                  label: isSeller ? 'Minha meta' : 'Meta do mês',
                  value: metaAtual <= 0
                      ? '—'
                      : '${(metaAtingida / metaAtual * 100).toStringAsFixed(0)}%',
                  color: _primaryColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<Map<String, dynamic>> _loadDashboardData(String lojaId) async {
    lojaId = StoreAccessGuard.requireLojaId(lojaId, context: 'DashboardHomeCards');
    final now = DateTime.now();
    final hojeInicio = DateTime(now.year, now.month, now.day);
    final hojeFim = hojeInicio.add(const Duration(days: 1));
    final scope = await AccessScopeService.loadIdentity();

    double vendasHoje = 0;
    int qtdEstoqueBaixo = 0;
    double metaAtual = 0;
    double metaAtingida = 0;

    try {
      final vendasBoxName = HiveBoxNames.vendas(lojaId);
      Box<Venda>? vendasBox;
      if (Hive.isBoxOpen(vendasBoxName)) {
        vendasBox = Hive.box<Venda>(vendasBoxName);
      } else {
        StoreAccessGuard.auditBoxAccess(vendasBoxName, lojaId, op: 'open');
        vendasBox = await Hive.openBox<Venda>(vendasBoxName);
      }
      for (final v in vendasBox.values) {
        if (v.lojaId != lojaId) continue;
        if (!AccessScopeService.canSeeSale(scope, v)) continue;
        if (!incluirVendaEmMetricas(v)) continue;
        final dt = v.data;
        if (dt.isAfter(hojeInicio) && dt.isBefore(hojeFim)) {
          vendasHoje += v.total;
        }
      }
    } catch (_) {}

    try {
      final produtosBoxName = HiveBoxNames.produtos(lojaId);
      Box<Produto>? produtosBox;
      if (Hive.isBoxOpen(produtosBoxName)) {
        produtosBox = Hive.box<Produto>(produtosBoxName);
      } else {
        StoreAccessGuard.auditBoxAccess(produtosBoxName, lojaId, op: 'open');
        produtosBox = await Hive.openBox<Produto>(produtosBoxName);
      }
      // Estoque baixo: vendedor consulta; indicador permanece (consulta).
      for (final p in produtosBox.values) {
        if (p.lojaId != lojaId) continue;
        if (p.isEstoqueBaixo) qtdEstoqueBaixo++;
      }
    } catch (_) {}

    try {
      final metaBoxName = 'metas_$lojaId';
      Box<Meta>? metaBox;
      if (Hive.isBoxOpen(metaBoxName)) {
        metaBox = Hive.box<Meta>(metaBoxName);
      } else {
        try {
          StoreAccessGuard.auditBoxAccess(metaBoxName, lojaId, op: 'open');
          metaBox = await Hive.openBox<Meta>(metaBoxName);
        } catch (_) {
          metaBox = null;
        }
      }
      if (metaBox != null) {
        final mesRef = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final sellerKeys = scope.sellerKeys;
        Meta? metaSeller;
        Meta? metaGeral;
        for (final m in metaBox.values) {
          if (m.lojaId != null && m.lojaId != lojaId) continue;
          if (m.mesRef != mesRef) continue;
          final vid = m.vendedorId.trim().toLowerCase();
          if (vid == 'geral' || vid.isEmpty) {
            metaGeral ??= m;
          } else if (scope.isSeller && sellerKeys.contains(vid)) {
            metaSeller ??= m;
          }
        }
        // Vendedor: só a própria meta (nunca a da loja).
        final escolhida = scope.isSeller ? metaSeller : (metaGeral ?? metaSeller);
        metaAtual = escolhida?.metaMensal ?? 0;
      }
      if (metaAtual > 0) {
        final vendasBoxName = HiveBoxNames.vendas(lojaId);
        if (Hive.isBoxOpen(vendasBoxName)) {
          final box = Hive.box<Venda>(vendasBoxName);
          final mesInicio = DateTime(now.year, now.month, 1);
          final mesFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          for (final v in box.values) {
            if (v.lojaId != lojaId) continue;
            if (!AccessScopeService.canSeeSale(scope, v)) continue;
            if (!incluirVendaEmMetricas(v)) continue;
            if (!v.data.isBefore(mesInicio) && !v.data.isAfter(mesFim)) {
              metaAtingida += v.total;
            }
          }
        }
      }
    } catch (_) {}

    return {
      'vendasHoje': vendasHoje,
      'qtdEstoqueBaixo': qtdEstoqueBaixo,
      'metaAtual': metaAtual,
      'metaAtingida': metaAtingida,
      'isSeller': scope.isSeller,
    };
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DashboardCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

