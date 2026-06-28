// Tela de diagnóstico local de sync de catálogo (dono/admin).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/catalogo_sync_diagnostics_access.dart';
import '../services/catalogo_sync_diagnostics_service.dart';
import '../services/store_identity_diagnostic_snapshot.dart';
import '../services/store_identity_diagnostics_service.dart';

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
  StoreIdentityDiagnosticSnapshot? _identidade;

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
      final identidade = await StoreIdentityDiagnosticsService.captureSafe();
      if (!mounted) return;
      setState(() {
        _tentativas = list;
        _identidade = identidade;
      });
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _copiarRelatorio(Map<String, dynamic>? record) async {
    final text = CatalogoSyncDiagnosticsService.buildCombinedSafeReport(
      attemptRecord: record,
      identitySnapshot: _identidade,
    );
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
            tooltip: 'Atualizar diagnóstico',
            onPressed: _carregando ? null : _recarregar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _secaoTitulo('Diagnóstico de identidade da loja'),
                if (_identidade == null)
                  const Text('Identidade indisponível neste aparelho.')
                else
                  _identidadeBloc(_identidade!),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _copiarRelatorio(ultima),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar relatório seguro'),
                ),
                const SizedBox(height: 24),
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
              width: 160,
              child: Text(label, style: const TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _identidadeBloc(StoreIdentityDiagnosticSnapshot snap) {
    final conflict = snap.profileHasLegacyConflict
        ? 'sim'
        : (snap.diagnosticDataCompleteness ==
                StoreIdentityDiagnosticCompleteness.unavailable
            ? 'indisponível'
            : 'não');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _linha(
          'Origem da loja ativa',
          StoreIdentityDiagnosticSnapshot.sourceLabel(
            snap.activeStoreResolutionSource,
          ),
        ),
        _linha(
          'Loja canônica do perfil',
          snap.profileCanonicalStoreAvailable ? 'disponível' : 'indisponível',
        ),
        _linha('Conflito remoto de perfil detectado', conflict),
        _linha(
          'Sessão vs canônica',
          StoreIdentityDiagnosticSnapshot.relationLabel(snap.sessionVsCanonical),
        ),
        _linha(
          'Sessão vs legado',
          StoreIdentityDiagnosticSnapshot.relationLabel(snap.sessionVsLegacy),
        ),
        _linha(
          'Resolvida vs canônica',
          StoreIdentityDiagnosticSnapshot.relationLabel(
            snap.resolvedVsCanonical,
          ),
        ),
        _linha(
          'Resolvida vs legado',
          StoreIdentityDiagnosticSnapshot.relationLabel(snap.resolvedVsLegacy),
        ),
        _linha(
          'Sessão = resolvida',
          StoreIdentityDiagnosticSnapshot.yesNoUnavailable(
            snap.sessionEqualsResolved,
          ),
        ),
        _linha(
          'Loja ativa vs canônica',
          StoreIdentityDiagnosticSnapshot.relationLabel(
            snap.activeStoreMatchesCanonical,
          ),
        ),
        _linha(
          'Loja ativa vs legado',
          StoreIdentityDiagnosticSnapshot.relationLabel(
            snap.activeStoreMatchesLegacy,
          ),
        ),
        _linha(
          'Completude do diagnóstico',
          StoreIdentityDiagnosticSnapshot.completenessLabel(
            snap.diagnosticDataCompleteness,
          ),
        ),
        _linha('Horário da captura', snap.capturedAtUtc.toIso8601String()),
      ],
    );
  }

  Widget _contextoBloc(Map<String, dynamic> record) {
    final ctx = record['contextoSanitizado'] as Map<String, dynamic>?;
    if (ctx == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _linha('Build', '${ctx['buildId'] ?? '—'}'),
        _linha('Host', '${ctx['host'] ?? '—'}'),
        _linha('Projeto Firebase', '${ctx['firebaseProjectId'] ?? '—'}'),
        _linha('Auth', '${ctx['authState'] ?? '—'}'),
        _linha('Token metadata', '${ctx['tokenMetadataState'] ?? '—'}'),
        if (ctx['identidadeLoja'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'Identidade na tentativa (relacional)',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            CatalogoSyncDiagnosticsService.buildIdentityReport(
              _snapshotFromMap(ctx['identidadeLoja'] as Map<String, dynamic>),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  StoreIdentityDiagnosticSnapshot _snapshotFromMap(Map<String, dynamic> map) {
    return StoreIdentityDiagnosticSnapshot(
      capturedAtUtc: DateTime.tryParse(
            (map['capturedAtUtc'] ?? '').toString(),
          ) ??
          DateTime.now().toUtc(),
      activeStoreResolutionSource: StoreIdentityResolutionSource.values.byName(
        (map['activeStoreResolutionSource'] ?? 'unavailable').toString(),
      ),
      profileCanonicalStoreAvailable:
          map['profileCanonicalStoreAvailable'] == true,
      profileHasLegacyConflict: map['profileHasLegacyConflict'] == true,
      sessionVsCanonical: StoreIdentityRelation.values.byName(
        (map['sessionVsCanonical'] ?? 'unavailable').toString(),
      ),
      sessionVsLegacy: StoreIdentityRelation.values.byName(
        (map['sessionVsLegacy'] ?? 'unavailable').toString(),
      ),
      resolvedVsCanonical: StoreIdentityRelation.values.byName(
        (map['resolvedVsCanonical'] ?? 'unavailable').toString(),
      ),
      resolvedVsLegacy: StoreIdentityRelation.values.byName(
        (map['resolvedVsLegacy'] ?? 'unavailable').toString(),
      ),
      sessionEqualsResolved: StoreIdentityRelation.values.byName(
        (map['sessionEqualsResolved'] ?? 'unavailable').toString(),
      ),
      activeStoreMatchesCanonical: StoreIdentityRelation.values.byName(
        (map['activeStoreMatchesCanonical'] ?? 'unavailable').toString(),
      ),
      activeStoreMatchesLegacy: StoreIdentityRelation.values.byName(
        (map['activeStoreMatchesLegacy'] ?? 'unavailable').toString(),
      ),
      profileStoreIdAvailable: map['profileStoreIdAvailable'] == true,
      profileOwnerOfAvailable: map['profileOwnerOfAvailable'] == true,
      profileLojaIdLegacyAvailable: map['profileLojaIdLegacyAvailable'] == true,
      legacyOwnerStoreIdAvailable: map['legacyOwnerStoreIdAvailable'] == true,
      diagnosticDataCompleteness:
          StoreIdentityDiagnosticCompleteness.values.byName(
        (map['diagnosticDataCompleteness'] ?? 'unavailable').toString(),
      ),
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
          : status == 'skipped'
              ? Icons.skip_next_outlined
              : status == 'failure'
                  ? Icons.error_outline
                  : Icons.hourglass_empty;
      final cor = status == 'success'
          ? Colors.green
          : status == 'skipped'
              ? Colors.blueGrey
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
              if (op['skipReason'] != null) 'Motivo: ${op['skipReason']}',
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
