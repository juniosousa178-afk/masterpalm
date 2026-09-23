import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../diagnostics/diagnostics.dart';
import '../../utils/role_utils.dart';

/// Platform admin: Saúde do Sistema (aggregates only, no cross-tenant PII).
class SystemHealthAdminScreen extends StatefulWidget {
  const SystemHealthAdminScreen({super.key});

  @override
  State<SystemHealthAdminScreen> createState() =>
      _SystemHealthAdminScreenState();
}

class _SystemHealthAdminScreenState extends State<SystemHealthAdminScreen> {
  bool _loading = true;
  String? _error;
  List<_StoreHealthRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = FirebaseAuth.instance.currentUser?.email;
      String tipo = '';
      try {
        final sessao = Hive.isBoxOpen('sessao')
            ? Hive.box('sessao')
            : await Hive.openBox('sessao');
        tipo = (sessao.get('tipo_usuario') as String?) ?? '';
      } catch (_) {}
      final role = RoleUtils.resolveRole(email: email, localRole: tipo);
      if (!role.isRoot && !RoleUtils.isMasterPlanAdminEmail(email)) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Acesso restrito a programador / admin de plataforma';
        });
        return;
      }

      await DiagnosticIncidentHistory.ensureHydrated();
      final byStore = <String, List<DiagnosticIncident>>{};
      for (final i in DiagnosticIncidentHistory.recent(limit: 200)) {
        byStore.putIfAbsent(i.storeId, () => []).add(i);
      }

      // Metadata-only store names (no products/customers).
      final names = <String, String>{};
      try {
        final snap = await FirebaseFirestore.instance
            .collection('lojas')
            .limit(200)
            .get(const GetOptions(source: Source.server));
        for (final d in snap.docs) {
          final data = d.data();
          names[d.id] =
              (data['nome'] ?? data['name'] ?? d.id).toString();
        }
      } catch (_) {
        // Rules may block listing; fall back to history keys only.
      }

      final ids = {...byStore.keys, ...names.keys}.toList()..sort();
      final rows = <_StoreHealthRow>[];
      for (final id in ids) {
        final incidents = byStore[id] ?? const <DiagnosticIncident>[];
        final health = incidents.isEmpty
            ? DiagnosticHealthStatus.healthy
            : DiagnosticHealthStatus.fromSeverities(
                incidents.map((e) => e.severity),
              );
        DateTime? last;
        for (final i in incidents) {
          if (last == null || i.timestamp.isAfter(last)) last = i.timestamp;
        }
        rows.add(_StoreHealthRow(
          storeId: id,
          displayName: names[id] ?? id,
          status: health,
          pending: incidents
              .where((i) =>
                  i.classification ==
                      DiagnosticClassification.stockPendingOperation ||
                  i.classification ==
                      DiagnosticClassification.stockOrphanPending)
              .length,
          stockDeltas: incidents
              .where((i) =>
                  i.classification ==
                  DiagnosticClassification.stockLocalRemoteMismatch)
              .length,
          aggregateMismatches: incidents
              .where((i) =>
                  i.classification ==
                  DiagnosticClassification.stockAggregateMismatch)
              .length,
          saleBindingErrors: incidents
              .where((i) =>
                  i.classification ==
                  DiagnosticClassification.saleMissingStockOperationBinding)
              .length,
          functionErrors: incidents
              .where((i) => i.module == DiagnosticModule.cloudFunction)
              .length,
          lastDiagnostic: last,
        ));
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saúde do Sistema — histórico disponível neste dispositivo'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Text(
                      'Saúde do Sistema — histórico disponível neste dispositivo. '
                      'Não é um painel em tempo real de todas as lojas. '
                      'Sem produtos/clientes de outros tenants.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('STORE')),
                          DataColumn(label: Text('STATUS')),
                          DataColumn(label: Text('PENDING')),
                          DataColumn(label: Text('STOCK_DELTAS')),
                          DataColumn(label: Text('AGG_MISMATCH')),
                          DataColumn(label: Text('SALE_BINDING')),
                          DataColumn(label: Text('FN_ERRORS')),
                          DataColumn(label: Text('LAST_DIAGNOSTIC')),
                        ],
                        rows: _rows
                            .map(
                              (r) => DataRow(
                                cells: [
                                  DataCell(Text('${r.displayName}\n${r.storeId}')),
                                  DataCell(Text(r.status.wire)),
                                  DataCell(Text('${r.pending}')),
                                  DataCell(Text('${r.stockDeltas}')),
                                  DataCell(Text('${r.aggregateMismatches}')),
                                  DataCell(Text('${r.saleBindingErrors}')),
                                  DataCell(Text('${r.functionErrors}')),
                                  DataCell(Text(
                                    r.lastDiagnostic?.toUtc().toIso8601String() ??
                                        '—',
                                  )),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _StoreHealthRow {
  _StoreHealthRow({
    required this.storeId,
    required this.displayName,
    required this.status,
    required this.pending,
    required this.stockDeltas,
    required this.aggregateMismatches,
    required this.saleBindingErrors,
    required this.functionErrors,
    required this.lastDiagnostic,
  });

  final String storeId;
  final String displayName;
  final DiagnosticHealthStatus status;
  final int pending;
  final int stockDeltas;
  final int aggregateMismatches;
  final int saleBindingErrors;
  final int functionErrors;
  final DateTime? lastDiagnostic;
}
