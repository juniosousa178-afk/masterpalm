// Recovery-mode-only panel for iPhone Safari variation stock diagnostic export.

import 'package:flutter/material.dart';

import '../services/sync_queue_recovery_mode.dart';
import '../services/variation_stock_recovery_diagnostic.dart';
import '../services/variation_stock_recovery_diagnostic_export.dart';

/// Visible only when [SyncQueueRecoveryMode.isActive].
class VariationStockRecoveryDiagnosticPanel extends StatefulWidget {
  const VariationStockRecoveryDiagnosticPanel({
    super.key,
    required this.storeId,
  });

  final String storeId;

  @override
  State<VariationStockRecoveryDiagnosticPanel> createState() =>
      _VariationStockRecoveryDiagnosticPanelState();
}

class _VariationStockRecoveryDiagnosticPanelState
    extends State<VariationStockRecoveryDiagnosticPanel> {
  final _filterCtrl = TextEditingController();
  final _service = VariationStockRecoveryDiagnosticService();
  bool _busy = false;
  VariationStockRecoveryDiagnosticSnapshot? _last;
  String? _error;

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _gerar() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!SyncQueueRecoveryMode.isActive) {
        throw VariationStockDiagnosticGuardException(
          'Modo de recuperação inactivo.',
        );
      }
      final snap = await _service.generate(
        storeId: widget.storeId,
        nameFilter: _filterCtrl.text,
      );
      if (!mounted) return;
      setState(() => _last = snap);
      await VariationStockRecoveryDiagnosticExporter.exportSnapshot(
        context,
        snap,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SyncQueueRecoveryMode.isActive) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final summary = _last?.summary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.65),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Diagnóstico de recuperação',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nenhuma sincronização ou alteração será feita.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _filterCtrl,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Filtrar produto (opcional)',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _gerar(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy || widget.storeId.trim().isEmpty ? null : _gerar,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_busy ? 'A gerar…' : 'Gerar diagnóstico'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: 10),
              Text(
                'Versão carregada: ${_last!.clientWebVersion}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Produtos com variação: ${summary.variableProductCount}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Produtos com qtd 0: ${summary.zeroQtyProductCount}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Intents pendentes: ${summary.pendingProductIntentCount}',
                style: theme.textTheme.bodySmall,
              ),
              if (summary.staleIntentCount > 0)
                Text(
                  'Intents com revisão antiga: ${summary.staleIntentCount}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
