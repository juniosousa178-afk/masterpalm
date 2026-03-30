import 'package:flutter/material.dart';

import '../models/catalog_avaliacao.dart';
import '../services/catalog_avaliacoes_service.dart';
import '../widgets/admin_catalog_avaliacao_card.dart';

/// Moderação de avaliações pendentes do catálogo — apenas [lojaId] atual.
class CatalogAvaliacoesModeracaoScreen extends StatefulWidget {
  final String lojaId;

  const CatalogAvaliacoesModeracaoScreen({
    super.key,
    required this.lojaId,
  });

  @override
  State<CatalogAvaliacoesModeracaoScreen> createState() =>
      _CatalogAvaliacoesModeracaoScreenState();
}

class _CatalogAvaliacoesModeracaoScreenState
    extends State<CatalogAvaliacoesModeracaoScreen> {
  final Set<String> _processandoIds = {};

  static const double _maxContentWidth = 680;

  void _snack(
    String msg, {
    bool sucesso = true,
  }) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(
            color: sucesso
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onErrorContainer,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
        backgroundColor: sucesso
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
      ),
    );
  }

  Future<void> _aprovar(CatalogAvaliacao a) async {
    final id = a.id;
    if (id.isEmpty || _processandoIds.contains(id)) return;
    setState(() => _processandoIds.add(id));
    try {
      await CatalogAvaliacoesService.aprovarAvaliacao(
        lojaId: widget.lojaId,
        avaliacaoId: id,
      );
      if (mounted) {
        _snack(
          'Avaliação aprovada. Ela já pode aparecer no catálogo público.',
          sucesso: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _snack('Erro ao aprovar: $e', sucesso: false);
      }
    } finally {
      if (mounted) {
        setState(() => _processandoIds.remove(id));
      }
    }
  }

  Future<void> _rejeitar(CatalogAvaliacao a) async {
    final id = a.id;
    if (id.isEmpty || _processandoIds.contains(id)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar avaliação?'),
        content: const Text(
          'O comentário deixará de ser exibido no catálogo. O registro permanece salvo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _processandoIds.add(id));
    try {
      await CatalogAvaliacoesService.rejeitarAvaliacao(
        lojaId: widget.lojaId,
        avaliacaoId: id,
      );
      if (mounted) {
        _snack(
          'Avaliação rejeitada. O registro foi mantido na base.',
          sucesso: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _snack('Erro ao rejeitar: $e', sucesso: false);
      }
    } finally {
      if (mounted) {
        setState(() => _processandoIds.remove(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderar avaliações'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return StreamBuilder<List<CatalogAvaliacao>>(
            stream:
                CatalogAvaliacoesService.watchPendentesPorLoja(widget.lojaId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 16),
                          Text(
                            'Não foi possível carregar as avaliações.\n${snap.error}',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final lista = snap.data ?? const <CatalogAvaliacao>[];
              if (lista.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 56,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma avaliação pendente',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Novos envios do catálogo aparecem aqui para aprovação.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final horizontal =
                  (constraints.maxWidth - _maxContentWidth) / 2 > 16
                      ? (constraints.maxWidth - _maxContentWidth) / 2
                      : 16.0;

              return ListView.separated(
                padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 24),
                itemCount: lista.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final a = lista[index];
                  final processando = _processandoIds.contains(a.id);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxContentWidth,
                      ),
                      child: AdminCatalogAvaliacaoCard(
                        avaliacao: a,
                        processando: processando,
                        onAprovar: () => _aprovar(a),
                        onRejeitar: () => _rejeitar(a),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
