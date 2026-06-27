// Tela de diagnóstico local de sync de catálogo (dono/admin).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/catalogo_sync_diagnostics_access.dart';
import '../services/catalogo_sync_diagnostics_service.dart';

class CatalogoSyncDiagnosticsScreen extends StatefulWidget {
  const CatalogoSyncDiagnosticsScreen({super.key});

  @override
  State<CatalogoSyncDiagnosticsScreen> createState() =>
      _CatalogoSyncDiagnosticsScreenState();
}

class _CatalogoSyncDiagnosticsScreenState
    extends State<CatalogoSyncDiagnosticsScreen> {
  bool _podeAcessar = false;
  bool _carregando = true;
  List<Map<String, dynamic>> _tentativas = [];

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final ok = await CatalogoSyncDiagnosticsAccess.podeAcessar();
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _podeAcessar = true);
    await _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() => _carregando = true);
    try {
      final list = await CatalogoSyncDiagnosticsService.listAttempts();
      if (!mounted) return;
      setState(() => _tentativas = list);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _copiarRelatorio(Map<String, dynamic> record) async {
    final text = CatalogoSyncDiagnosticsService.buildSafeReport(record);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relatório seguro copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_podeAcessar) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ultima = _tentativas.isNotEmpty ? _tentativas.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico de sincronização do catálogo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar lista local',
            onPressed: _carregando ? null : _recarregar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (ultima == null)
                  const Text('Nenhuma tentativa registrada neste aparelho.')
                else ...[
                  _secaoTitulo('Última tentativa'),
                  _linha('ID curto', '${ultima['attemptIdCurto'] ?? '—'}'),
                  _linha('Origem', '${ultima['origin'] ?? '—'}'),
                  _linha('Horário', '${ultima['timestampUtc'] ?? '—'}'),
                  _contextoBloc(ultima),
                  const SizedBox(height: 12),
                  _secaoTitulo('Operações'),
                  ..._operacoesWidgets(ultima),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _copiarRelatorio(ultima),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar relatório seguro'),
                  ),
                ],
                if (_tentativas.length > 1) ...[
                  const SizedBox(height: 24),
                  _secaoTitulo('Histórico (${_tentativas.length})'),
                  ..._tentativas.skip(1).map(_historicoTile),
                ],
              ],
            ),
    );
  }

  Widget _secaoTitulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      );

  Widget _linha(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label, style: const TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _contextoBloc(Map<String, dynamic> record) {
    final ctx = record['contextoSanitizado'] as Map<String, dynamic>?;
    if (ctx == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _linha('Build', '${ctx['buildId'] ?? '—'}'),
        _linha('Host', '${ctx['host'] ?? '—'}'),
        _linha('Projeto Firebase', '${ctx['firebaseProjectId'] ?? '—'}'),
        _linha('Loja da sessão', '${ctx['sessionStoreIdMasked'] ?? '—'}'),
        _linha('Loja resolvida', '${ctx['resolvedStoreIdMasked'] ?? '—'}'),
        _linha('UID', '${ctx['authUidMasked'] ?? '—'}'),
        _linha('Auth', '${ctx['authState'] ?? '—'}'),
        _linha('Token metadata', '${ctx['tokenMetadataState'] ?? '—'}'),
      ],
    );
  }

  List<Widget> _operacoesWidgets(Map<String, dynamic> record) {
    final ops =
        (record['operacoes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (ops.isEmpty) {
      return [const Text('Nenhuma operação registrada.')];
    }
    return ops.map((op) {
      final nome = op['operationName'] ?? '—';
      final status = op['status'] ?? '—';
      final code = op['firebaseErrorCode'];
      final icone = status == 'success'
          ? Icons.check_circle_outline
          : status == 'failure'
              ? Icons.error_outline
              : Icons.hourglass_empty;
      final cor = status == 'success'
          ? Colors.green
          : status == 'failure'
              ? Colors.orange
              : Colors.grey;
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icone, color: cor),
          title: Text('$nome: $status'),
          subtitle: Text(
            [
              if (code != null) 'Código: $code',
              'Path: ${op['pathMasked'] ?? '—'}',
              if (op['errorMessageSanitized'] != null)
                'Msg: ${op['errorMessageSanitized']}',
            ].join('\n'),
          ),
          isThreeLine: true,
        ),
      );
    }).toList();
  }

  Widget _historicoTile(Map<String, dynamic> record) {
    return ListTile(
      title: Text('${record['attemptIdCurto'] ?? '—'} — ${record['origin']}'),
      subtitle: Text('${record['timestampUtc'] ?? '—'}'),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        onPressed: () => _copiarRelatorio(record),
      ),
    );
  }
}
