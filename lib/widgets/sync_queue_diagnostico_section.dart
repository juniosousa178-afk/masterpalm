// Painel mínimo de diagnóstico da fila offline → Firestore (somente programador / tela diagnóstico).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/sync_queue_service.dart';

/// Filtro da lista de itens.
enum _SyncQueueFilter { all, active, dead }

class SyncQueueDiagnosticoSection extends StatefulWidget {
  const SyncQueueDiagnosticoSection({super.key});

  @override
  State<SyncQueueDiagnosticoSection> createState() =>
      _SyncQueueDiagnosticoSectionState();
}

class _SyncQueueDiagnosticoSectionState extends State<SyncQueueDiagnosticoSection> {
  static final _df = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  SyncQueueMetrics? _metrics;
  List<SyncQueueDiagnosticEntry> _entries = [];
  _SyncQueueFilter _filter = _SyncQueueFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await SyncQueueService.getMetrics();
      final list = await SyncQueueService.listDiagnosticEntries();
      if (mounted) {
        setState(() {
          _metrics = m;
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtMs(int ms) {
    if (ms <= 0) return '—';
    try {
      return _df.format(DateTime.fromMillisecondsSinceEpoch(ms));
    } catch (_) {
      return '—';
    }
  }

  String _shortId(String id) {
    if (id.length <= 20) return id;
    return '${id.substring(0, 12)}…${id.substring(id.length - 6)}';
  }

  List<SyncQueueDiagnosticEntry> _filteredList() {
    switch (_filter) {
      case _SyncQueueFilter.active:
        return _entries.where((e) => !e.deadLetter).toList();
      case _SyncQueueFilter.dead:
        return _entries.where((e) => e.deadLetter).toList();
      case _SyncQueueFilter.all:
        return List<SyncQueueDiagnosticEntry>.from(_entries);
    }
  }

  Future<void> _confirm(
    String title,
    String body,
    Future<void> Function() onYes,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok == true) await onYes();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.sync_alt, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fila de sincronização (Hive → Firestore)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading && _metrics == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_metrics != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'Pendentes ativos',
                      value: '${_metrics!.activePending}',
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: 'Falhas preservadas',
                      value: '${_metrics!.deadLetter}',
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: 'Total na fila',
                      value: '${_metrics!.total}',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: _filter == _SyncQueueFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _SyncQueueFilter.all),
                  ),
                  ChoiceChip(
                    label: const Text('Pendentes'),
                    selected: _filter == _SyncQueueFilter.active,
                    onSelected: (_) =>
                        setState(() => _filter = _SyncQueueFilter.active),
                  ),
                  ChoiceChip(
                    label: const Text('Falhas preservadas'),
                    selected: _filter == _SyncQueueFilter.dead,
                    onSelected: (_) =>
                        setState(() => _filter = _SyncQueueFilter.dead),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_metrics!.deadLetter > 0)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () async {
                                await _confirm(
                                  'Reprocessar todos',
                                  'Zera tentativas e reenvia todos os itens em falha preservada. '
                                  'Continuar?',
                                  () async {
                                    final n = await SyncQueueService
                                        .retryAllDeadLetters();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Reprocessados: $n itens',
                                          ),
                                        ),
                                      );
                                      await _load();
                                    }
                                  },
                                );
                              },
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('Reprocessar todos (falhas)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _loading
                            ? null
                            : () async {
                                await _confirm(
                                  'Limpar falhas preservadas',
                                  'Remove da fila somente entradas em falha preservada. '
                                  'Os dados locais (vendas/clientes) não são apagados. '
                                  'Isto não desfaz a necessidade de sincronizar na nuvem. '
                                  'Continuar?',
                                  () async {
                                    final n = await SyncQueueService
                                        .clearDeadLetterItems();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Removidas $n entradas da fila',
                                          ),
                                        ),
                                      );
                                      await _load();
                                    }
                                  },
                                );
                              },
                        icon: Icon(Icons.delete_sweep, color: Colors.red.shade700),
                        label: Text(
                          'Limpar falhas preservadas',
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Nenhum item na fila.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        e.deadLetter
                            ? 'Falha preservada · ${e.typeLabel}'
                            : 'Pendente · ${e.typeLabel}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'id ${_shortId(e.id)} · loja …${e.lojaId.length > 8 ? e.lojaId.substring(e.lojaId.length - 8) : e.lojaId} · key ${e.entityKey}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'Tentativas: ${e.attemptCount} · Criado: ${_fmtMs(e.createdAtMs)} · Última falha: ${_fmtMs(e.lastAttemptAtMs)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if ((e.lastError ?? '').isNotEmpty)
                            Text(
                              'Último erro: ${e.lastError}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade800,
                              ),
                            ),
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () async {
                                    final ok =
                                        await SyncQueueService.retryItem(e.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            ok
                                                ? 'Reprocessar: enviado'
                                                : 'Falha ao reprocessar',
                                          ),
                                        ),
                                      );
                                      await _load();
                                    }
                                  },
                            child: const Text('Reprocessar'),
                          ),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () async {
                                await _confirm(
                                  'Remover item',
                                  'Remove só esta entrada da fila de sync. '
                                  'Não apaga venda/cliente no armazenamento local.',
                                  () async {
                                    final ok =
                                        await SyncQueueService.removeItem(e.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            ok
                                                ? 'Item removido da fila'
                                                : 'Item não encontrado',
                                          ),
                                        ),
                                      );
                                      await _load();
                                    }
                                  },
                                );
                              },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade800,
                            ),
                            child: const Text('Remover'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
