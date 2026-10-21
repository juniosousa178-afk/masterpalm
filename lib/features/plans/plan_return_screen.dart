// Página de retorno do checkout de planos (Mercado Pago → app).
//
// O estado exibido vem só do backend (acesso efetivo do usuário autenticado). A query do
// Mercado Pago (`status=approved`, `collection_status`…) não é lida: o webhook ativa o plano.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/master_plan_access_models.dart';
import '../../core/master_plan_admin_messages.dart' show masterPlanIdLabel;
import '../../services/checkout_service.dart' show normalizeCheckoutPlanId;
import '../../services/planos_service.dart' show PlanInfo;
import 'plan_return_link.dart';

enum PlanReturnState { signedOut, confirmed, awaitingConfirmation, unavailable }

class PlanReturnStatus {
  const PlanReturnStatus(this.state, {this.planLabel});

  final PlanReturnState state;

  /// Nome do plano contratado (apenas em [PlanReturnState.confirmed]).
  final String? planLabel;
}

typedef PlanReturnStatusLoader = Future<PlanReturnStatus> Function(
    PlanReturnRef ref);

const _kActivePaidStatuses = {'active', 'cancel_scheduled'};

/// Decide o estado a partir do acesso efetivo do servidor ([access]) e, para troca de plano,
/// do documento do usuário ([plan]). Sem dados suficientes, nunca confirma.
PlanReturnStatus evaluatePlanReturn({
  required PlanReturnRef ref,
  required EffectivePlanAccessDto? access,
  PlanInfo? plan,
}) {
  if (access == null) {
    return const PlanReturnStatus(PlanReturnState.unavailable);
  }
  final status = (access.effectiveStatus ?? '').trim().toLowerCase();
  final paidActive = access.accessSource == 'paid_subscription' &&
      _kActivePaidStatuses.contains(status);
  if (!paidActive) {
    return const PlanReturnStatus(PlanReturnState.awaitingConfirmation);
  }
  final contracted =
      normalizeCheckoutPlanId(access.contractedPlanId ?? access.effectivePlanId);
  switch (ref.kind) {
    case PlanReturnKind.oneTime:
      if (ref.planId == null ||
          contracted != normalizeCheckoutPlanId(ref.planId)) {
        return const PlanReturnStatus(PlanReturnState.awaitingConfirmation);
      }
    case PlanReturnKind.recurring:
      if (!access.subscription.hasMaskedSubscriptionId) {
        return const PlanReturnStatus(PlanReturnState.awaitingConfirmation);
      }
    case PlanReturnKind.planChange:
      if (plan == null || plan.hasPendingPlanChange) {
        return const PlanReturnStatus(PlanReturnState.awaitingConfirmation);
      }
  }
  return PlanReturnStatus(
    PlanReturnState.confirmed,
    planLabel: masterPlanIdLabel(contracted),
  );
}

class PlanReturnScreen extends StatefulWidget {
  const PlanReturnScreen({
    super.key,
    required this.ref,
    required this.loader,
    required this.onOpenApp,
    this.autoRefreshInterval = const Duration(seconds: 5),
    this.maxAutoRefreshes = 12,
  });

  /// `null` quando o path não é um retorno de plano reconhecido.
  final PlanReturnRef? ref;
  final PlanReturnStatusLoader loader;
  final void Function(BuildContext context) onOpenApp;

  /// Releitura automática enquanto o webhook não chega; `null` desativa.
  final Duration? autoRefreshInterval;
  final int maxAutoRefreshes;

  @override
  State<PlanReturnScreen> createState() => _PlanReturnScreenState();
}

class _PlanReturnScreenState extends State<PlanReturnScreen> {
  PlanReturnStatus? _status;
  bool _loading = false;
  int _autoRefreshes = 0;
  Timer? _timer;

  bool get _validRef => widget.ref?.isValid ?? false;

  @override
  void initState() {
    super.initState();
    if (_validRef) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    setState(() => _loading = true);
    PlanReturnStatus status;
    try {
      status = await widget.loader(widget.ref!);
    } catch (_) {
      status = const PlanReturnStatus(PlanReturnState.unavailable);
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
    final interval = widget.autoRefreshInterval;
    if (status.state == PlanReturnState.awaitingConfirmation &&
        interval != null &&
        _autoRefreshes < widget.maxAutoRefreshes) {
      _timer = Timer(interval, () {
        _autoRefreshes++;
        if (mounted) _load();
      });
    }
  }

  bool get _isPlanChange => widget.ref?.kind == PlanReturnKind.planChange;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (!_validRef) {
      content = _StateView(
        key: const Key('plan-return-invalid'),
        icon: Icons.link_off,
        title: 'Link de retorno inválido',
        message: 'Abra o MasterPalm para conferir sua assinatura.',
        primaryLabel: 'Abrir o MasterPalm',
        onPrimary: () => widget.onOpenApp(context),
      );
    } else if (_status == null) {
      content = const Column(
        key: Key('plan-return-loading'),
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Verificando sua assinatura…'),
        ],
      );
    } else {
      content = _viewFor(context, _status!);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Assinatura MasterPalm')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _viewFor(BuildContext context, PlanReturnStatus status) {
    void openApp() => widget.onOpenApp(context);
    switch (status.state) {
      case PlanReturnState.signedOut:
        return _StateView(
          key: const Key('plan-return-signed-out'),
          icon: Icons.lock_outline,
          title: 'Entre para ver sua assinatura',
          message:
              'Por segurança, o status da assinatura só aparece para a conta que fez a compra. '
              'Entre no MasterPalm com essa conta.',
          primaryLabel: 'Entrar no MasterPalm',
          onPrimary: openApp,
        );
      case PlanReturnState.confirmed:
        final label = status.planLabel;
        return _StateView(
          key: const Key('plan-return-confirmed'),
          icon: Icons.check_circle_outline,
          title: 'Sua assinatura está ativa',
          message: label == null ? null : 'Plano atual: $label.',
          primaryLabel: 'Abrir o MasterPalm',
          onPrimary: openApp,
        );
      case PlanReturnState.awaitingConfirmation:
        return _StateView(
          key: const Key('plan-return-awaiting'),
          icon: Icons.hourglass_top,
          title: _isPlanChange
              ? 'Estamos confirmando a troca de plano'
              : 'Estamos confirmando sua assinatura',
          message:
              'Se você concluiu o pagamento no Mercado Pago, a confirmação costuma chegar '
              'em poucos minutos. Esta página verifica de novo automaticamente.',
          primaryLabel: 'Atualizar',
          onPrimary: _loading ? null : _load,
          secondaryLabel: 'Abrir o MasterPalm',
          onSecondary: openApp,
        );
      case PlanReturnState.unavailable:
        return _StateView(
          key: const Key('plan-return-unavailable'),
          icon: Icons.cloud_off,
          title: 'Não foi possível verificar agora',
          message: 'Verifique sua conexão e tente novamente.',
          primaryLabel: 'Tentar novamente',
          onPrimary: _loading ? null : _load,
          secondaryLabel: 'Abrir o MasterPalm',
          onSecondary: openApp,
        );
    }
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        if (secondaryLabel != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
        ],
      ],
    );
  }
}
