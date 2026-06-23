import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/master_plan_access_models.dart';
import '../../core/master_plan_admin_messages.dart';
import '../../services/master_plan_admin_service.dart';
import '../../utils/role_utils.dart';
import 'master_user_plan_detail_screen.dart';

/// Mestre > Assinaturas e Acessos — somente masterpalm26@gmail.com.
class MasterPlanAccessScreen extends StatefulWidget {
  const MasterPlanAccessScreen({super.key});

  @override
  State<MasterPlanAccessScreen> createState() => _MasterPlanAccessScreenState();
}

class _MasterPlanAccessScreenState extends State<MasterPlanAccessScreen> {
  final _service = MasterPlanAdminService();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  MasterPlanAccessSummary? _summary;
  final List<MasterPlanUserRow> _users = [];
  String? _nextPageToken;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _authorized {
    final email = FirebaseAuth.instance.currentUser?.email;
    return RoleUtils.isMasterPlanAdminEmail(email);
  }

  Future<void> _loadInitial() async {
    if (!_authorized) {
      setState(() {
        _loading = false;
        _error = 'Acesso restrito à administração Mestre.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _service.fetchSummary();
      final page = await _service.listUsers(pageSize: 25);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _users
          ..clear()
          ..addAll(page.users);
        _nextPageToken = page.nextPageToken;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _nextPageToken == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.listUsers(
        pageSize: 25,
        pageToken: _nextPageToken,
      );
      if (!mounted) return;
      setState(() {
        _users.addAll(page.users);
        _nextPageToken = page.nextPageToken;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _searchExact() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await _service.fetchUserDetails(
        targetUid: q.contains('@') ? null : q,
        targetEmail: q.contains('@') ? q : null,
      );
      if (!mounted) return;
      final user = details['user'] is Map
          ? Map<String, dynamic>.from(details['user'] as Map)
          : <String, dynamic>{};
      final uid = user['uid']?.toString() ?? q;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MasterUserPlanDetailScreen(targetUid: uid),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mestre > Assinaturas e Acessos'),
      ),
      body: !_authorized
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'Acesso restrito à administração Mestre.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadInitial,
              child: _loading && _users.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        if (_summary != null) _SummaryCard(summary: _summary!),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Consultar UID ou e-mail exato',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: _searchExact,
                            ),
                          ),
                          onSubmitted: (_) => _searchExact(),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Usuários',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._users.map(_UserTile.new),
                        if (_hasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _loadingMore
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
                                      onPressed: _loadMore,
                                      child: const Text('Carregar mais'),
                                    ),
                            ),
                          ),
                      ],
                    ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final MasterPlanAccessSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Total de usuários: ${summary.totalCanonicalUsers ?? '—'}'),
            Text(
              'Renovações canceladas: ${summary.totalRenewalCancelled ?? '—'}',
            ),
            Text(
              'manualOverride legado: ${summary.manualOverridePending ? 'pendente' : summary.manualOverrideCount ?? '—'}',
            ),
            Text(
              'manual_grant legado: ${summary.manualGrantPending ? 'métrica pendente' : '—'}',
            ),
            Text(
              summary.totalActiveCourtesyPending
                  ? 'Cortesias ativas: métrica pendente'
                  : 'Cortesias ativas: ${summary.totalActiveCourtesy ?? '—'}',
            ),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile(this.row);

  final MasterPlanUserRow row;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(row.emailMasked ?? row.uid),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (row.lojaNome != null && row.lojaNome!.isNotEmpty)
              Text('Loja: ${row.lojaNome}'),
            Text(
              'Contratado: ${masterPlanIdLabel(row.contractedPlanId)} · '
              'Efetivo: ${masterPlanIdLabel(row.effectivePlanId)}',
            ),
            Text(
              '${masterPlanAccessSourceLabel(row.accessSource)} · '
              '${row.daysRemaining ?? 0} dias restantes',
            ),
            if (row.courtesy.active)
              Text(
                'Cortesia ativa (${masterPlanIdLabel(row.courtesy.planId)})',
                style: const TextStyle(color: Colors.green),
              ),
            if (row.renewal.cancelAtPeriodEnd)
              const Text(
                'Renovação cancelada',
                style: TextStyle(color: Colors.orange),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MasterUserPlanDetailScreen(targetUid: row.uid),
            ),
          );
        },
      ),
    );
  }
}
