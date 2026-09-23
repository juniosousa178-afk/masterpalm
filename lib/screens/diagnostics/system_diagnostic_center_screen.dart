import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../diagnostics/diagnostics.dart';
import '../../services/loja_id_service.dart';

/// Configurações → Diagnóstico do Sistema
class SystemDiagnosticCenterScreen extends StatefulWidget {
  const SystemDiagnosticCenterScreen({super.key});

  @override
  State<SystemDiagnosticCenterScreen> createState() =>
      _SystemDiagnosticCenterScreenState();
}

class _SystemDiagnosticCenterScreenState
    extends State<SystemDiagnosticCenterScreen> {
  final _center = DiagnosticCenterService();
  DiagnosticResult? _result;
  List<DiagnosticIncident> _recent = const [];
  bool _loading = false;
  String? _storeId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final sid = await LojaIdService.get();
    final recent = await _center.recentErrors(storeId: sid);
    if (!mounted) return;
    setState(() {
      _storeId = sid;
      _recent = recent;
      _result = _center.lastResult;
    });
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _center.runDiagnostic(storeId: _storeId);
      final recent = await _center.recentErrors(storeId: r.storeId);
      if (!mounted) return;
      setState(() {
        _result = r;
        _recent = recent;
        _storeId = r.storeId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    try {
      final art = _center.exportLast();
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: art.pretty));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSON copiado: ${art.fileName}')),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${art.fileName}');
      await file.writeAsBytes(art.bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: art.fileName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exportação: $e')),
      );
    }
  }

  Color _statusColor(DiagnosticHealthStatus? s) {
    switch (s) {
      case DiagnosticHealthStatus.critical:
        return Colors.red.shade700;
      case DiagnosticHealthStatus.warning:
        return Colors.orange.shade800;
      case DiagnosticHealthStatus.healthy:
        return Colors.green.shade700;
      case null:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final build = _center.buildIdentity();
    final health = _result?.health;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico do Sistema'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SYSTEM_STATUS=${health?.wire ?? '—'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _statusColor(health),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'LAST_DIAGNOSTIC_AT=${_result?.generatedAt.toUtc().toIso8601String() ?? '—'}',
                  ),
                  Text('STORE_ID=${_storeId ?? '—'}'),
                  Text('CURRENT_BUILD_ID=${build['CLIENT_BUILD_ID']}'),
                  Text('APP_VERSION=${build['APP_VERSION']}'),
                  Text('GIT_COMMIT=${build['CLIENT_GIT_COMMIT']}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Somente leitura: não altera estoque, vendas nem exclusões.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _run,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.health_and_safety),
                label: Text(_loading ? 'A executar…' : 'Executar diagnóstico'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final recent =
                      await _center.recentErrors(storeId: _storeId);
                  if (!mounted) return;
                  setState(() => _recent = recent);
                },
                icon: const Icon(Icons.history),
                label: const Text('Últimos erros'),
              ),
              OutlinedButton.icon(
                onPressed: _result == null ? null : _export,
                icon: const Icon(Icons.download),
                label: const Text('Exportar diagnóstico'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text('Resumo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._result!.summary.entries.map(
              (e) => Text('${e.key}=${e.value}'),
            ),
            const SizedBox(height: 16),
            Text(
              'Incidentes (${_result!.incidents.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._result!.incidents.take(40).map(_incidentTile),
          ],
          if (_recent.isNotEmpty && _result == null) ...[
            const SizedBox(height: 16),
            Text(
              'Últimos erros (${_recent.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._recent.map(_incidentTile),
          ],
        ],
      ),
    );
  }

  Widget _incidentTile(DiagnosticIncident i) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(i.userTitle),
        subtitle: Text(
          '${i.severity.wire} · ${i.classification}\n${i.userMessage}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SAFE_NEXT_ACTION=${i.safeNextAction}'),
                  Text('rootCauseStatus=${i.rootCauseStatus.wire}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Detalhes técnicos',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text('CLASSIFICATION=${i.classification}'),
                  Text('TRACE_ID=${i.traceId}'),
                  if (i.stage != null) Text('STAGE=${i.stage}'),
                  if (i.productIds.isNotEmpty)
                    Text('PRODUCT_ID=${i.productIds.join(',')}'),
                  if (i.saleId != null) Text('SALE_ID=${i.saleId}'),
                  if (i.sourceOperationId != null)
                    Text('SOURCE_OPERATION_ID=${i.sourceOperationId}'),
                  if (i.stockOperationId != null)
                    Text('STOCK_OPERATION_ID=${i.stockOperationId}'),
                  if (i.firebaseCode != null)
                    Text('FIREBASE_CODE=${i.firebaseCode}'),
                  if (i.functionName != null)
                    Text('FUNCTION=${i.functionName}'),
                  Text('APP_VERSION=${i.appVersion ?? '—'}'),
                  Text('GIT_COMMIT=${i.gitCommit ?? '—'}'),
                  Text('BUILD_ID=${i.buildId ?? '—'}'),
                  if (i.technicalMessage != null)
                    Text('technical=${i.technicalMessage}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
