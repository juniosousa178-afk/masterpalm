import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/master_plan_access_models.dart';
import '../../core/master_plan_admin_messages.dart';
import '../../services/master_plan_admin_service.dart';
import '../../services/planos_service.dart';
import '../../utils/role_utils.dart';

class MasterUserPlanDetailScreen extends StatefulWidget {
  const MasterUserPlanDetailScreen({super.key, required this.targetUid});

  final String targetUid;

  @override
  State<MasterUserPlanDetailScreen> createState() =>
      _MasterUserPlanDetailScreenState();
}

class _MasterUserPlanDetailScreenState extends State<MasterUserPlanDetailScreen> {
  final _service = MasterPlanAdminService();
  bool _loading = true;
  bool _actionLoading = false;
  String? _error;
  String? _auditWarning;
  Map<String, dynamic>? _details;
  List<MasterPlanAuditAction> _audit = [];

  static const _grantablePlans = [
    PlanId.basicMonthly,
    PlanId.intermediateMonthly,
    PlanId.proMonthly,
    PlanId.proYearly,
    PlanId.lifetime,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _authorized =>
      RoleUtils.isMasterPlanAdminEmail(FirebaseAuth.instance.currentUser?.email);

  Future<void> _load() async {
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
      _auditWarning = null;
    });
    try {
      final details = await _service.fetchUserDetails(
        targetUid: widget.targetUid,
      );
      if (!mounted) return;
      setState(() => _details = details);
    } catch (e) {
      debugPrint('[MasterPlanDetail] load details failed $e');
      if (!mounted) return;
      setState(() {
        _details = null;
        _error = masterPlanUserDetailErrorMessage(e);
      });
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    try {
      final audit = await _service.listAuditActions(targetUid: widget.targetUid);
      if (!mounted) return;
      setState(() => _audit = audit);
    } catch (e, st) {
      debugPrint('[MasterPlanDetail] audit load failed $e $st');
      if (!mounted) return;
      setState(() {
        _audit = [];
        _auditWarning =
            'Não foi possível carregar o histórico administrativo deste usuário.';
      });
    }
  }

  EffectivePlanAccessDto? get _planAccess {
    final pa = _details?['planAccess'];
    if (pa is Map) {
      return EffectivePlanAccessDto.fromMap(Map<String, dynamic>.from(pa));
    }
    return null;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await action();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Operação concluída com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _showGrantDialog() async {
    String planId = PlanId.intermediateMonthly;
    String type = 'temporary';
    DateTime? expiresAt = DateTime.now().add(const Duration(days: 30));
    final reasonCtrl = TextEditingController();
    final confirmPermanentCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Liberar cortesia'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: planId,
                  decoration: const InputDecoration(labelText: 'Plano'),
                  items: _grantablePlans
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(masterPlanIdLabel(p)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => planId = v ?? planId),
                ),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'temporary', child: Text('Temporária')),
                    DropdownMenuItem(value: 'permanent', child: Text('Permanente')),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                if (type == 'temporary')
                  ListTile(
                    title: Text(
                      expiresAt != null
                          ? 'Validade: ${expiresAt!.day}/${expiresAt!.month}/${expiresAt!.year}'
                          : 'Selecionar data final',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: expiresAt ?? DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setLocal(() => expiresAt = picked);
                    },
                  ),
                if (type == 'permanent') ...[
                  const Text(
                    'Não há pagamento vinculado a cortesia permanente.',
                    style: TextStyle(color: Colors.orange),
                  ),
                  TextField(
                    controller: confirmPermanentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Digite LIBERAR PERMANENTEMENTE',
                    ),
                  ),
                ],
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) return;
                if (type == 'temporary' && expiresAt == null) return;
                if (type == 'permanent' &&
                    confirmPermanentCtrl.text.trim() !=
                        'LIBERAR PERMANENTEMENTE') {
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      reasonCtrl.dispose();
      confirmPermanentCtrl.dispose();
      return;
    }

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    confirmPermanentCtrl.dispose();

    await _runAction(() async {
      await _service.grantCourtesy(
        targetUid: widget.targetUid,
        planId: planId,
        type: type,
        expiresAt: type == 'temporary' ? expiresAt : null,
        reason: reason,
        requestId: MasterPlanAdminService.newRequestId(),
      );
    });
  }

  Future<void> _showExtendDialog() async {
    final pa = _planAccess;
    if (pa == null || !pa.courtesy.active || pa.courtesy.permanent) return;
    DateTime? newDate = DateTime.now().add(const Duration(days: 30));
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Estender cortesia'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  newDate != null
                      ? 'Nova validade: ${newDate!.day}/${newDate!.month}/${newDate!.year}'
                      : 'Selecionar nova data',
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: newDate ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setLocal(() => newDate = picked);
                },
              ),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Motivo'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty || newDate == null) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    await _runAction(() async {
      await _service.extendCourtesy(
        targetUid: widget.targetUid,
        expiresAt: newDate!,
        reason: reason,
        requestId: MasterPlanAdminService.newRequestId(),
      );
    });
  }

  Future<void> _showRevokeDialog() async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revogar cortesia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta ação remove somente o acesso manual de cortesia. '
              'Não cancela assinatura, não gera cobrança e não altera o plano contratado.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motivo'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    await _runAction(() async {
      await _service.revokeCourtesy(
        targetUid: widget.targetUid,
        reason: reason,
        requestId: MasterPlanAdminService.newRequestId(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _details?['user'] is Map
        ? Map<String, dynamic>.from(_details!['user'] as Map)
        : <String, dynamic>{};
    final pa = _planAccess;
    final subs = _details?['subscriptions'] is List ? _details!['subscriptions'] as List : const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do usuário')),
      body: !_authorized
          ? Center(child: Text(_error ?? 'Acesso restrito à administração Mestre.'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _loading ? null : _load,
                              child: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('E-mail: ${user['email'] ?? '—'}'),
                        Text('UID: ${user['uid'] ?? widget.targetUid}'),
                        Text('Loja: ${user['lojaId'] ?? '—'}'),
                        const Divider(),
                        if (pa != null) ...[
                          Text('Plano contratado: ${masterPlanIdLabel(pa.contractedPlanId)}'),
                          Text('Acesso efetivo: ${masterPlanIdLabel(pa.effectivePlanId)}'),
                          Text('Origem: ${masterPlanAccessSourceLabel(pa.accessSource)}'),
                          Text('Status: ${pa.effectiveStatus ?? '—'}'),
                          Text('Dias restantes: ${pa.daysRemaining ?? '—'}'),
                          if (pa.renewal.cancelAtPeriodEnd)
                            const Text('Renovação cancelada no fim do período'),
                          if (pa.courtesy.active) ...[
                            Text(
                              'Cortesia: ${masterPlanIdLabel(pa.courtesy.planId)} '
                              '${pa.courtesy.permanent ? '(permanente)' : 'até ${pa.courtesy.expiresAt ?? '—'}'}',
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        if (_actionLoading) const LinearProgressIndicator(),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: _actionLoading ? null : _showGrantDialog,
                              child: const Text('Liberar cortesia'),
                            ),
                            if (pa?.courtesy.active == true && !pa!.courtesy.permanent)
                              OutlinedButton(
                                onPressed: _actionLoading ? null : _showExtendDialog,
                                child: const Text('Estender cortesia'),
                              ),
                            if (pa?.courtesy.active == true)
                              OutlinedButton(
                                onPressed: _actionLoading ? null : _showRevokeDialog,
                                child: const Text('Revogar cortesia'),
                              ),
                          ],
                        ),
                        const Divider(),
                        const Text('Assinaturas recentes', style: TextStyle(fontWeight: FontWeight.bold)),
                        ...subs.map((s) {
                          if (s is! Map) return const SizedBox.shrink();
                          final m = Map<String, dynamic>.from(s);
                          return ListTile(
                            dense: true,
                            title: Text(masterPlanIdLabel(m['planId']?.toString())),
                            subtitle: Text(
                              '${m['status'] ?? '—'} · ${m['maskedProviderSubscriptionId'] ?? '—'}',
                            ),
                          );
                        }),
                        const Divider(),
                        const Text('Histórico administrativo', style: TextStyle(fontWeight: FontWeight.bold)),
                        if (_auditWarning != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _auditWarning!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ..._audit.map(
                          (a) => ListTile(
                            dense: true,
                            title: Text('${a.actionType ?? '—'} · ${a.createdAt ?? ''}'),
                            subtitle: Text(a.reason ?? ''),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
