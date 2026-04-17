// lib/screens/catalog_payment_support_screen.dart
// Forense leve: leitura do snapshot de pagamento catálogo MP (root; backend reforça).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/catalog_payment_support_service.dart';
import '../themes/app_colors.dart';
import '../utils/catalog_payment_support_nav.dart';
import '../utils/role_utils.dart';

typedef CatalogPaymentSupportFetcher = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> payload,
);

/// Parâmetros opcionais via [RouteSettings.arguments] (Map) ou query string (web).
@immutable
class CatalogPaymentSupportRouteParams {
  const CatalogPaymentSupportRouteParams({
    this.lojaId,
    this.orderId,
    this.externalReference,
    this.paymentId,
    this.autoQuery = false,
  });

  final String? lojaId;
  final String? orderId;
  final String? externalReference;
  final String? paymentId;
  final bool autoQuery;

  static const Set<String> _allowedKeys = {
    'lojaId',
    'orderId',
    'paymentId',
    'externalReference',
    'autoQuery',
    'auto',
  };

  /// Mescla argumentos de rota e query (web). [queryParameters] costuma ser [Uri.base.queryParameters].
  static CatalogPaymentSupportRouteParams merge({
    Object? routeArguments,
    Map<String, String>? queryParameters,
  }) {
    final m = <String, String>{};
    void put(String k, String? v) {
      final t = v?.trim();
      if (t == null || t.isEmpty) return;
      if (!_allowedKeys.contains(k)) return;
      m[k] = t;
    }

    if (routeArguments is Map) {
      for (final e in routeArguments.entries) {
        put(e.key.toString(), e.value?.toString());
      }
    }
    if (queryParameters != null) {
      for (final e in queryParameters.entries) {
        put(e.key, e.value);
      }
    }

    final autoRaw = m['autoQuery'] ?? m['auto'];
    final auto = autoRaw == '1' || autoRaw == 'true' || autoRaw == 'yes';
    m.remove('autoQuery');
    m.remove('auto');

    return CatalogPaymentSupportRouteParams(
      lojaId: m['lojaId'],
      orderId: m['orderId'],
      externalReference: m['externalReference'],
      paymentId: m['paymentId'],
      autoQuery: auto,
    );
  }
}

class CatalogPaymentSupportScreen extends StatefulWidget {
  const CatalogPaymentSupportScreen({
    super.key,
    this.fetcher,
    this.routeArguments,
    @visibleForTesting this.bypassRootCheck = false,
  });

  /// Testes: injeta resposta mock; produção usa [CatalogPaymentSupportService].
  final CatalogPaymentSupportFetcher? fetcher;

  /// [Navigator.pushNamed(..., arguments: {...})] ou rota nomeada com Map.
  final Object? routeArguments;

  /// Apenas testes de widget: não valida e-mail root.
  @visibleForTesting
  final bool bypassRootCheck;

  @override
  State<CatalogPaymentSupportScreen> createState() =>
      _CatalogPaymentSupportScreenState();
}

class _CatalogPaymentSupportScreenState extends State<CatalogPaymentSupportScreen> {
  final _lojaCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController();

  bool _loading = false;
  String? _errorText;
  Map<String, dynamic>? _lastResponse;
  bool _initialRouteApplied = false;
  bool _autoQueryScheduled = false;

  @override
  void initState() {
    super.initState();
    if (!widget.bypassRootCheck &&
        !RoleUtils.isRootEmail(FirebaseAuth.instance.currentUser?.email)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consulta permitida apenas para conta root/admin.'),
          ),
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialRouteApplied) return;
    _initialRouteApplied = true;
    _applyInitialRouteParams();
  }

  void _applyInitialRouteParams() {
    final qp = kIsWeb ? Uri.base.queryParameters : null;
    final p = CatalogPaymentSupportRouteParams.merge(
      routeArguments: widget.routeArguments,
      queryParameters: qp,
    );
    if (p.lojaId != null) _lojaCtrl.text = p.lojaId!;
    final orderLine = p.externalReference ?? p.orderId;
    if (orderLine != null) _orderCtrl.text = orderLine;
    if (p.paymentId != null) _paymentCtrl.text = p.paymentId!;

    if (p.autoQuery && !_autoQueryScheduled) {
      _autoQueryScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_payloadValid()) _consultar();
      });
    }
  }

  bool _payloadValid() {
    final payload = CatalogPaymentSupportService.buildPayload(
      lojaId: _lojaCtrl.text,
      orderId: _orderCtrl.text,
      paymentId: _paymentCtrl.text,
    );
    return payload.isNotEmpty;
  }

  void _limpar() {
    FocusScope.of(context).unfocus();
    _lojaCtrl.clear();
    _orderCtrl.clear();
    _paymentCtrl.clear();
    setState(() {
      _loading = false;
      _errorText = null;
      _lastResponse = null;
    });
  }

  @override
  void dispose() {
    _lojaCtrl.dispose();
    _orderCtrl.dispose();
    _paymentCtrl.dispose();
    super.dispose();
  }

  Future<void> _consultar() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _errorText = null;
      _lastResponse = null;
    });

    final payload = CatalogPaymentSupportService.buildPayload(
      lojaId: _lojaCtrl.text,
      orderId: _orderCtrl.text,
      paymentId: _paymentCtrl.text,
    );

    if (payload.isEmpty) {
      setState(() {
        _loading = false;
        _errorText = 'Preencha paymentId ou pedido (orderId / externalReference).';
      });
      return;
    }

    try {
      final fetch = widget.fetcher ??
          ((Map<String, dynamic> p) =>
              CatalogPaymentSupportService().fetchSnapshot(p));
      final map = await fetch(payload);
      if (!mounted) return;
      setState(() {
        _lastResponse = map;
        _loading = false;
        final um = userFacingMessageForSnapshot(map);
        _errorText = um;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = messageForFunctionsException(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _copyId(String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    showCatalogPaymentSupportCopyFeedback(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _lastResponse != null;
    final showEmptyHint = !hasResult && !_loading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suporte — pagamento catálogo MP'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Limpar e nova consulta',
            onPressed: _loading ? null : _limpar,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showEmptyHint) const _EmptyStateHint(),
            if (!showEmptyHint)
              Text(
                'Consulta somente leitura.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            const SizedBox(height: 12),
            _FieldWithCopy(
              controller: _lojaCtrl,
              label: 'lojaId',
              testKey: const Key('field_loja'),
              onCopy: _copyId,
            ),
            const SizedBox(height: 12),
            _FieldWithCopy(
              controller: _orderCtrl,
              label: 'orderId / externalReference',
              helperText: 'Mesmo campo para os dois (como no backend).',
              testKey: const Key('field_order'),
              onCopy: _copyId,
            ),
            const SizedBox(height: 12),
            _FieldWithCopy(
              controller: _paymentCtrl,
              label: 'paymentId',
              testKey: const Key('field_payment'),
              onCopy: _copyId,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _consultar(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _consultar,
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppColors.primary,
                    ),
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(_loading ? 'Consultando…' : 'Consultar'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loading ? null : _limpar,
                  child: const Text('Limpar'),
                ),
              ],
            ),
            if (_errorText != null && _lastResponse == null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: _errorText!),
            ],
            if (_lastResponse != null) ...[
              const SizedBox(height: 20),
              _SnapshotBody(
                response: _lastResponse!,
                topBannerMessage: _errorText,
                onCopyId: _copyId,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyStateHint extends StatelessWidget {
  const _EmptyStateHint();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Como consultar',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '• Pesquise por lojaId + orderId (ou externalReference no mesmo campo).\n'
              '• Ou consulte diretamente por paymentId (se já houver _mp_webhook_processed, o backend pode resolver loja/pedido).\n'
              '• Web (opcional): ?lojaId=…&orderId=…&paymentId=…&autoQuery=true',
              style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey[800]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldWithCopy extends StatelessWidget {
  const _FieldWithCopy({
    required this.controller,
    required this.label,
    required this.onCopy,
    this.helperText,
    this.testKey,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final Key? testKey;
  final void Function(String) onCopy;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: testKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Copiar valor do campo',
          icon: const Icon(Icons.copy, size: 20),
          onPressed: () => onCopy(controller.text),
        ),
      ),
      textInputAction: textInputAction ?? TextInputAction.next,
      onSubmitted: onSubmitted,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.orange.shade900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotBody extends StatelessWidget {
  const _SnapshotBody({
    required this.response,
    required this.topBannerMessage,
    required this.onCopyId,
  });

  final Map<String, dynamic> response;
  final String? topBannerMessage;
  final void Function(String value) onCopyId;

  static String _fmtMs(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v.toInt() : int.tryParse(v.toString());
    if (n == null) return '—';
    return DateFormat('dd/MM/yyyy HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(n));
  }

  @override
  Widget build(BuildContext context) {
    final status = response['status']?.toString() ?? '';
    final summary = response['summary'];
    final indicators = response['indicators'];
    final timeline = response['timeline'];
    final webhook = response['webhookProcessed'];
    final validation = response['validationRejection'];

    if (status != 'ok' || summary is! Map) {
      final reason = response['reason']?.toString() ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topBannerMessage != null) _ErrorBanner(message: topBannerMessage!),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                reason.isNotEmpty ? reason : 'Resposta: $status',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      );
    }

    final sm = Map<String, dynamic>.from(summary);
    final ind = indicators is Map
        ? Map<String, dynamic>.from(Map<Object?, Object?>.from(indicators))
        : <String, dynamic>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topBannerMessage != null) ...[
          _ErrorBanner(message: topBannerMessage!),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resumo', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _kvCopy('lojaId', sm['lojaId']?.toString() ?? '', onCopyId),
                _kvCopy('orderId', sm['orderId']?.toString() ?? '', onCopyId),
                _kvCopy('externalReference', sm['externalReference']?.toString() ?? '', onCopyId),
                _kvCopy('paymentId', sm['paymentId']?.toString() ?? '', onCopyId),
                if (sm['correlationIdPix'] != null &&
                    sm['correlationIdPix'].toString().isNotEmpty)
                  _kvCopy(
                    'correlationId (pix)',
                    sm['correlationIdPix'].toString(),
                    onCopyId,
                  ),
                if (sm['correlationIdPreference'] != null &&
                    sm['correlationIdPreference'].toString().isNotEmpty)
                  _kvCopy(
                    'correlationId (preference)',
                    sm['correlationIdPreference'].toString(),
                    onCopyId,
                  ),
                _kv('provider', sm['provider']?.toString()),
                _kv('tipo', sm['tipo']?.toString()),
                _kv('status local', sm['statusLocal']?.toString()),
                _kv('status pagamento (pedido)', sm['statusPagamento']?.toString()),
                _kv('payment status (doc MP)', sm['paymentStatusMpDoc']?.toString()),
                _kv('total esperado', sm['totalExpected']?.toString()),
                _kv('criado', _fmtMs(sm['createdAtMs'])),
                _kv('pago (local)', _fmtMs(sm['paidAtMs'])),
                _kv('atualizado', _fmtMs(sm['updatedAtMs'])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (webhook is Map) _WebhookCard(webhook: Map<String, dynamic>.from(webhook)),
        if (validation is Map) ...[
          const SizedBox(height: 12),
          _ValidationCard(v: Map<String, dynamic>.from(validation)),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Indicadores', style: TextStyle(fontWeight: FontWeight.bold)),
                if (ind['webhookProcessedOutcome'] != null &&
                    ind['webhookProcessedOutcome'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'webhookProcessedOutcome: ${ind['webhookProcessedOutcome']}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 8),
                _IndicatorChips(ind: ind),
                if (ind['validationFailureReason'] != null &&
                    ind['validationFailureReason'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Motivo validação: ${ind['validationFailureReason']}',
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                if (ind['validationRejectSuperseded'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Rejeição anterior superseded pelo webhook bem-sucedido.',
                      style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (timeline is List && timeline.isNotEmpty)
                  ...timeline.map((e) {
                    if (e is! Map) return const SizedBox.shrink();
                    final m = Map<String, dynamic>.from(Map<Object?, Object?>.from(e));
                    final ev = m['event']?.toString() ?? '';
                    final at = _fmtMs(m['atMs']);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(ev, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(at),
                    );
                  })
                else
                  const Text('Sem eventos na timeline.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WebhookCard extends StatelessWidget {
  const _WebhookCard({required this.webhook});

  final Map<String, dynamic> webhook;

  @override
  Widget build(BuildContext context) {
    if (webhook['exists'] != true) {
      return const Card(
        child: ListTile(
          title: Text('Webhook processado'),
          subtitle: Text('Sem registro em _mp_webhook_processed.'),
        ),
      );
    }
    String fmt(dynamic v) {
      if (v == null) return '—';
      final n = v is num ? v.toInt() : int.tryParse(v.toString());
      if (n == null) return '—';
      return DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(n));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Webhook processado', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _kv('status', webhook['status']?.toString()),
            _kv(
              'effectiveOutcome',
              webhook['effectiveOutcome']?.toString() ?? webhook['status']?.toString(),
            ),
            _kv('processado em', fmt(webhook['processedAtMs'])),
            _kv('reenvio ignorado em', fmt(webhook['duplicateWebhookAtMs'])),
            if (webhook['duplicateWebhookOutcome'] != null)
              _kv('nota reenvio', webhook['duplicateWebhookOutcome']?.toString()),
          ],
        ),
      ),
    );
  }
}

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({required this.v});

  final Map<String, dynamic> v;

  @override
  Widget build(BuildContext context) {
    if (v['recordExists'] != true) {
      return const SizedBox.shrink();
    }
    String fmt(dynamic x) {
      if (x == null) return '—';
      final n = x is num ? x.toInt() : int.tryParse(x.toString());
      if (n == null) return '—';
      return DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(n));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Validação (webhook)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _kv('ativa', v['active']?.toString()),
            _kv('motivo', v['reason']?.toString()),
            _kv('superseded', v['supersededBySuccessfulWebhook']?.toString()),
            _kv('registrado em', fmt(v['recordedAtMs'])),
          ],
        ),
      ),
    );
  }
}

Widget _kv(String k, String? v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Text(k, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ),
        Expanded(child: Text(v ?? '—', style: const TextStyle(fontSize: 14))),
      ],
    ),
  );
}

Widget _kvCopy(String k, String v, void Function(String) onCopyId) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(k, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ),
        Expanded(
          child: SelectableText(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 14)),
        ),
        if (v.isNotEmpty)
          IconButton(
            tooltip: 'Copiar ID',
            onPressed: () => onCopyId(v),
            icon: const Icon(Icons.copy, size: 18),
          ),
      ],
    ),
  );
}

class _IndicatorChips extends StatelessWidget {
  const _IndicatorChips({required this.ind});

  final Map<String, dynamic> ind;

  static Color _bg(String key, bool on) {
    if (!on) return Colors.grey.shade200;
    switch (key) {
      case 'hasPersistError':
      case 'hasValidationFailure':
        return Colors.red.shade50;
      case 'hasNoopAlreadyPaid':
        return Colors.amber.shade50;
      case 'hasDuplicateIgnored':
        return Colors.lightBlue.shade50;
      case 'hasProviderSuccess':
      case 'hasPersistSuccess':
      case 'hasWebhookApproved':
      case 'hasMaterialNewEffect':
        return Colors.green.shade50;
      case 'hasWebhookProcessed':
        return Colors.teal.shade50;
      default:
        return Colors.grey.shade200;
    }
  }

  static Color _border(String key, bool on) {
    if (!on) return Colors.grey.shade400;
    switch (key) {
      case 'hasPersistError':
      case 'hasValidationFailure':
        return Colors.red.shade300;
      case 'hasNoopAlreadyPaid':
        return Colors.amber.shade400;
      case 'hasDuplicateIgnored':
        return Colors.lightBlue.shade300;
      case 'hasProviderSuccess':
      case 'hasPersistSuccess':
      case 'hasWebhookApproved':
      case 'hasMaterialNewEffect':
        return Colors.green.shade300;
      case 'hasWebhookProcessed':
        return Colors.teal.shade300;
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool b(String k) => ind[k] == true;

    final items = <({String key, String label, bool value})>[
      (key: 'hasProviderSuccess', label: 'Provider success', value: b('hasProviderSuccess')),
      (key: 'hasPersistSuccess', label: 'Persist success', value: b('hasPersistSuccess')),
      (key: 'hasPersistError', label: 'Persist error', value: b('hasPersistError')),
      (key: 'hasWebhookProcessed', label: 'Webhook processado', value: b('hasWebhookProcessed')),
      (key: 'hasWebhookApproved', label: 'Webhook approved', value: b('hasWebhookApproved')),
      (key: 'hasValidationFailure', label: 'Validation failure', value: b('hasValidationFailure')),
      (key: 'hasDuplicateIgnored', label: 'Duplicate ignored', value: b('hasDuplicateIgnored')),
      (key: 'hasMaterialNewEffect', label: 'Material new effect', value: b('hasMaterialNewEffect')),
      (key: 'hasNoopAlreadyPaid', label: 'Noop já pago', value: b('hasNoopAlreadyPaid')),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map(
            (e) => Chip(
              label: Text(
                e.value ? '✓ ${e.label}' : '○ ${e.label}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: e.value ? FontWeight.w600 : FontWeight.normal,
                  color: e.value ? Colors.black87 : Colors.grey.shade700,
                ),
              ),
              backgroundColor: _bg(e.key, e.value),
              side: BorderSide(color: _border(e.key, e.value)),
            ),
          )
          .toList(),
    );
  }
}
