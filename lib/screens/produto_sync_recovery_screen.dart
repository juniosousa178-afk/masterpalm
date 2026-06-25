// Tela de recuperação assistida de sincronização de estoque (dono/admin).

import 'package:flutter/material.dart';

import '../services/produto_sync_recovery_access.dart';
import '../services/produto_sync_recovery_mask_util.dart';
import '../services/produto_sync_recovery_models.dart';
import '../services/produto_sync_recovery_preview_service.dart';
import '../services/produto_sync_recovery_service.dart';
import '../services/produto_sync_recovery_session_service.dart';

class ProdutoSyncRecoveryScreen extends StatefulWidget {
  const ProdutoSyncRecoveryScreen({super.key});

  @override
  State<ProdutoSyncRecoveryScreen> createState() =>
      _ProdutoSyncRecoveryScreenState();
}

class _ProdutoSyncRecoveryScreenState extends State<ProdutoSyncRecoveryScreen> {
  RecoveryPreview? _preview;
  List<RecoveryJournalEntry> _journal = [];
  bool _carregando = false;
  bool _podeAcessar = false;
  String? _mensagem;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final ok = await ProdutoSyncRecoveryAccess.podeAcessarRecuperacao();
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _podeAcessar = true);
    await _atualizarDiagnostico();
  }

  Future<void> _atualizarDiagnostico() async {
    setState(() {
      _carregando = true;
      _mensagem = null;
    });
    try {
      final preview = await ProdutoSyncRecoveryPreviewService.gerarPreview();
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _journal = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mensagem = 'Erro ao gerar diagnóstico');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _corrigirSessao() async {
    final preview = _preview;
    if (preview == null || !preview.sessionMismatch.podeReparar) return;

    final canonical = preview.identity.lojaCanonica;
    if (canonical == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Corrigir sessão local?'),
        content: Text(
          'A sessão deste aparelho passará a usar a loja canônica '
          '(${ProdutoSyncRecoveryMaskUtil.mascararLojaId(canonical)}). '
          'Isso altera apenas o armazenamento local.',
        ),
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

    if (confirm != true) return;

    final record =
        await ProdutoSyncRecoverySessionService.repararSessaoParaLojaCanonica(
      lojaCanonica: canonical,
    );

    if (!mounted) return;
    setState(() {
      _mensagem = record != null
          ? 'Sessão atualizada para loja canônica'
          : 'Não foi possível reparar a sessão';
    });
    await _atualizarDiagnostico();
  }

  Future<void> _prepararRecuperacao() async {
    final preview = _preview;
    if (preview == null) return;

    final result = await ProdutoSyncRecoveryService.prepararRecuperacao(preview);
    if (!mounted) return;
    setState(() {
      _journal = result.entradasJournal;
      _mensagem = result.mensagem;
    });
  }

  Future<void> _recuperarElegiveis() async {
    final preview = _preview;
    if (preview == null || _journal.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar produtos elegíveis?'),
        content: Text(
          'Serão reidentificados ${preview.elegiveis} produto(s) elegível(is) '
          'com novo identificador local seguro e enfileirados para sincronização.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RECUPERAR PRODUTOS ELEGÍVEIS'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _carregando = true);
    try {
      final result = await ProdutoSyncRecoveryService.recuperarProdutosElegiveis(
        preview: preview,
        journalEntradas: _journal,
      );
      if (!mounted) return;
      setState(() => _mensagem = result.mensagem);
      await _atualizarDiagnostico();
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  bool get _podeRecuperar {
    final p = _preview;
    if (p == null) return false;
    return p.identity.sessaoAlinhada && p.elegiveis > 0 && _journal.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (!_podeAcessar) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final preview = _preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperação de sincronização de estoque'),
      ),
      body: _carregando && preview == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_mensagem != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_mensagem!),
                  ),
                if (preview != null) ...[
                  _infoTile(
                    'Loja da sessão',
                    ProdutoSyncRecoveryMaskUtil.mascararLojaId(
                      preview.identity.sessaoStoreId,
                    ),
                  ),
                  _infoTile(
                    'Loja canônica',
                    ProdutoSyncRecoveryMaskUtil.mascararLojaId(
                      preview.identity.lojaCanonica,
                    ),
                  ),
                  _infoTile(
                    'Status',
                    preview.identity.sessaoAlinhada ? 'Alinhada' : 'Divergente',
                  ),
                  _infoTile('Produtos locais (sessão)',
                      '${preview.produtosLocaisSessao}'),
                  _infoTile('Produtos locais (canônica)',
                      '${preview.produtosLocaisCanonica}'),
                  _infoTile(
                    'Produtos na nuvem',
                    preview.produtosRemotos?.toString() ??
                        (preview.offline ? 'Indisponível (offline)' : '—'),
                  ),
                  _infoTile(
                    'Itens pendentes na fila',
                    '${preview.filaPendentes}',
                  ),
                  _infoTile(
                    'Itens bloqueados (dead-letter)',
                    '${preview.filaDeadLetter}',
                  ),
                  _infoTile('Produtos elegíveis', '${preview.elegiveis}'),
                  _infoTile(
                    'Exigem ação manual',
                    '${preview.manuais}',
                  ),
                  if (preview.offline)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Modo offline: contagens remotas indisponíveis.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: _carregando ? null : _atualizarDiagnostico,
                        child: const Text('Atualizar diagnóstico'),
                      ),
                      if (preview.sessionMismatch.podeReparar)
                        OutlinedButton(
                          onPressed: _carregando ? null : _corrigirSessao,
                          child: const Text('Corrigir sessão local'),
                        ),
                      OutlinedButton(
                        onPressed: _carregando ||
                                !preview.identity.sessaoAlinhada ||
                                preview.elegiveis == 0
                            ? null
                            : _prepararRecuperacao,
                        child: const Text('Preparar recuperação'),
                      ),
                      FilledButton(
                        onPressed:
                            _carregando || !_podeRecuperar ? null : _recuperarElegiveis,
                        child: const Text('Recuperar produtos elegíveis'),
                      ),
                    ],
                  ),
                  if (_journal.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Journal: ${_journal.length} entrada(s) preparada(s)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
