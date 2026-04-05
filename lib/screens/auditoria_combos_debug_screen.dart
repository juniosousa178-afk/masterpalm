// lib/screens/auditoria_combos_debug_screen.dart
// Ferramenta interna: auditoria passiva de receitas de combo (somente leitura).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../services/combo_receita_auditoria_service.dart';
import '../services/store_resolver_facade.dart';

enum _ModoLista { todos, pendentes, ranking }

class AuditoriaCombosDebugScreen extends StatefulWidget {
  const AuditoriaCombosDebugScreen({super.key});

  @override
  State<AuditoriaCombosDebugScreen> createState() =>
      _AuditoriaCombosDebugScreenState();
}

class _AuditoriaCombosDebugScreenState
    extends State<AuditoriaCombosDebugScreen> {
  Future<RelatorioAuditoriaCombos?>? _future;
  _ModoLista _modo = _ModoLista.todos;
  RelatorioAuditoriaCombos? _ultimoRelatorio;

  @override
  void initState() {
    super.initState();
    _future = _executar();
  }

  Future<RelatorioAuditoriaCombos?> _executar() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      return null;
    }
    final boxName = HiveBoxNames.produtos(lojaId);
    final Box<Produto> box = Hive.isBoxOpen(boxName)
        ? Hive.box<Produto>(boxName)
        : await Hive.openBox<Produto>(boxName);
    final r = ComboReceitaAuditoriaService.auditarLoja(
      lojaId: lojaId,
      todosProdutos: box.values,
    );
    if (mounted) setState(() => _ultimoRelatorio = r);
    return r;
  }

  static String _labelCombo(StatusComboAuditoria s) {
    switch (s) {
      case StatusComboAuditoria.ok:
        return 'OK';
      case StatusComboAuditoria.okComRessalvas:
        return 'OK_COM_RESSALVAS';
      case StatusComboAuditoria.pendente:
        return 'PENDENTE';
      case StatusComboAuditoria.critico:
        return 'CRITICO';
    }
  }

  static String _labelLinha(StatusLinhaReceitaAuditoria s) {
    switch (s) {
      case StatusLinhaReceitaAuditoria.okCanonico:
        return 'OK_CANONICO';
      case StatusLinhaReceitaAuditoria.semProductIdMasResolvivel:
        return 'SEM_PRODUCT_ID_MAS_RESOLVIVEL';
      case StatusLinhaReceitaAuditoria.ambiguo:
        return 'AMBIGUO';
      case StatusLinhaReceitaAuditoria.produtoNaoEncontrado:
        return 'PRODUTO_NAO_ENCONTRADO';
      case StatusLinhaReceitaAuditoria.productIdInvalido:
        return 'PRODUCT_ID_INVALIDO';
      case StatusLinhaReceitaAuditoria.receitaLinhaInconsistente:
        return 'RECEITA_VAZIA_OU_INCONSISTENTE';
    }
  }

  Color _corCombo(StatusComboAuditoria s) {
    switch (s) {
      case StatusComboAuditoria.ok:
        return Colors.green.shade700;
      case StatusComboAuditoria.okComRessalvas:
        return Colors.amber.shade800;
      case StatusComboAuditoria.pendente:
        return Colors.deepOrange.shade700;
      case StatusComboAuditoria.critico:
        return Colors.red.shade700;
    }
  }

  List<AuditoriaComboResultado> _listaParaModo(RelatorioAuditoriaCombos r) {
    switch (_modo) {
      case _ModoLista.todos:
        return r.combos;
      case _ModoLista.pendentes:
        return r.combos
            .where((c) => c.statusGeral != StatusComboAuditoria.ok)
            .toList();
      case _ModoLista.ranking:
        return r.rankingPorGravidade;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Auditoria de combos'),
            Text(
              'Somente leitura · Hive local',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copiar JSON',
            icon: const Icon(Icons.data_object),
            onPressed: _ultimoRelatorio == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(
                      text: _ultimoRelatorio!.comoJsonIndentado(),
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('JSON copiado')),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Copiar texto formatado',
            icon: const Icon(Icons.copy),
            onPressed: _ultimoRelatorio == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(
                      text: _ultimoRelatorio!.comoTextoFormatado(),
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Relatório copiado')),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _future = _executar();
            }),
          ),
        ],
      ),
      body: FutureBuilder<RelatorioAuditoriaCombos?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erro: ${snap.error}'),
              ),
            );
          }
          final rel = snap.data;
          if (rel == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Não foi possível carregar: loja indefinida ou box de produtos fechado.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final lista = _listaParaModo(rel);
          final res = rel.resumo;

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _executar());
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumo executivo',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('lojaId: ${res.lojaId}'),
                        Text('Combos analisados: ${res.totalCombosAnalisados}'),
                        Text('Combos 100% OK: ${res.totalCombos100PorcentoOk}'),
                        Text(
                          'Combos com pendência: ${res.totalCombosComPendencia}',
                        ),
                        Text(
                          'Componentes auditados: ${res.totalComponentesAuditados}',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Por status de linha:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        ...res.contagemPorStatusLinha.entries.map(
                          (e) => Text('  ${e.key}: ${e.value}'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Visualização',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todos os combos'),
                      selected: _modo == _ModoLista.todos,
                      onSelected: (_) =>
                          setState(() => _modo = _ModoLista.todos),
                    ),
                    ChoiceChip(
                      label: const Text('Só pendentes'),
                      selected: _modo == _ModoLista.pendentes,
                      onSelected: (_) =>
                          setState(() => _modo = _ModoLista.pendentes),
                    ),
                    ChoiceChip(
                      label: const Text('Ranking por gravidade'),
                      selected: _modo == _ModoLista.ranking,
                      onSelected: (_) =>
                          setState(() => _modo = _ModoLista.ranking),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _modo == _ModoLista.pendentes
                      ? 'Exibe combos com status ≠ OK (inclui ressalvas).'
                      : _modo == _ModoLista.ranking
                          ? 'Ordem: CRITICO → PENDENTE → OK_COM_RESSALVAS → OK.'
                          : 'Lista na ordem do Hive (sem ordenação por gravidade).',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                if (lista.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Nenhum combo nesta visualização.')),
                  )
                else
                  ...lista.map((c) => _ComboCard(
                        resultado: c,
                        labelCombo: _labelCombo,
                        labelLinha: _labelLinha,
                        corCombo: _corCombo,
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComboCard extends StatelessWidget {
  const _ComboCard({
    required this.resultado,
    required this.labelCombo,
    required this.labelLinha,
    required this.corCombo,
  });

  final AuditoriaComboResultado resultado;
  final String Function(StatusComboAuditoria) labelCombo;
  final String Function(StatusLinhaReceitaAuditoria) labelLinha;
  final Color Function(StatusComboAuditoria) corCombo;

  @override
  Widget build(BuildContext context) {
    final c = resultado;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: c.statusGeral != StatusComboAuditoria.ok,
        title: Text(
          c.nomeCombo,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${labelCombo(c.statusGeral)} · ${c.quantidadeItensReceita} itens na receita',
          style: TextStyle(color: corCombo(c.statusGeral), fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  'Combo productId: ${c.productIdCombo.isEmpty ? "—" : c.productIdCombo}\n'
                  'Slug: ${c.slugCombo.isEmpty ? "—" : c.slugCombo}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(c.observacaoCombo, style: const TextStyle(fontSize: 12)),
                if (c.acoesRecomendadasCombo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text('Ações sugeridas:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ...c.acoesRecomendadasCombo.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• $a', style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
                const Divider(),
                const Text('Componentes da receita',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                ...c.linhas.map((l) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Linha ${l.indice} · ${labelLinha(l.status)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'nome="${l.nomeSalvo}" slug="${l.slugSalvo}" '
                              'productId="${l.productIdSalvo}" qtd=${l.quantidadeExigida}',
                              style: const TextStyle(
                                  fontSize: 11, fontFamily: 'monospace'),
                            ),
                            if (l.produtoResolvidoNome != null)
                              Text(
                                'Resolvido (diagnóstico): ${l.produtoResolvidoNome} '
                                '(${l.produtoResolvidoId ?? "sem id"})',
                                style: const TextStyle(fontSize: 11),
                              ),
                            if (l.candidatosNomes != null &&
                                l.candidatosNomes!.isNotEmpty)
                              Text(
                                'Candidatos: ${l.candidatosNomes!.join(", ")}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.orange.shade900),
                              ),
                            Text(l.observacaoTecnica,
                                style: const TextStyle(fontSize: 11)),
                            Text('→ ${l.acaoRecomendada}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade700)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
