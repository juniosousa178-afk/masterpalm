// Aviso visual: pipeline concluído no estoque, compra cancelada depois (só informativo).

import 'package:flutter/material.dart';

import '../core/compra_item_pipeline_constants.dart';
import '../models/compra_item_pipeline.dart';

/// Regra única de exibição: concluído no estoque + compra cancelada após conclusão.
bool compraPipelineDeveExibirOrigemCancelada(CompraItemPipeline? p) {
  if (p == null) return false;
  return p.estado == CompraItemPipelineEstado.concluidoNoEstoque &&
      p.compraCanceladaAposConclusao;
}

/// Faixa informativa para telas com espaço (ex.: topo do formulário de produto).
class CompraPipelineOrigemCanceladaNotice extends StatelessWidget {
  const CompraPipelineOrigemCanceladaNotice({super.key, this.pipeline});

  final CompraItemPipeline? pipeline;

  @override
  Widget build(BuildContext context) {
    if (!compraPipelineDeveExibirOrigemCancelada(pipeline)) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final bg = cs.secondaryContainer.withOpacity(0.45);
    final fg = cs.onSecondaryContainer;
    return Semantics(
      label:
          'Produto concluído no estoque; a compra de origem foi cancelada depois. Informação histórica.',
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.history_rounded, size: 20, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Origem cancelada após conclusão',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Item já estava no estoque; a compra foi cancelada depois. '
                      'Só rastreio — não exige ação automática.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: fg.withOpacity(0.92),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip compacto para listas (cards).
class CompraPipelineOrigemCanceladaChip extends StatelessWidget {
  const CompraPipelineOrigemCanceladaChip({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message:
          'Produto concluído no estoque; a compra de origem foi cancelada depois.',
      child: Chip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: Icon(Icons.history_rounded, size: 16, color: cs.onSecondaryContainer),
        label: const Text('Origem cancelada'),
        labelStyle: TextStyle(fontSize: 11.5, color: cs.onSecondaryContainer),
        backgroundColor: cs.secondaryContainer.withOpacity(0.55),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}
