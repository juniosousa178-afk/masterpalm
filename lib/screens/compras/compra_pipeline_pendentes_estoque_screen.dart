// lib/screens/compras/compra_pipeline_pendentes_estoque_screen.dart
// Hub compra → precificação → estoque (leitura + navegação; sem alterar pipeline).

import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../core/compra_item_pipeline_constants.dart';
import '../../core/hive_box_names.dart';
import '../../models/compra_item_pipeline.dart';
import '../../models/produto.dart';
import '../../services/compra_item_pipeline_store.dart';
import '../../services/store_resolver_facade.dart';
import '../../widgets/compra_pipeline_origem_cancelada_notice.dart';
import '../precificacao_universal_screen.dart';
import '../produto_form_screen.dart';

enum _FiltroHub { pendentes, rastreio, todos }

enum _OrdenacaoHub {
  /// Mais recente primeiro ([CompraItemPipeline.atualizadoEm] desc).
  recentes,
  fornecedorAz,
  referenciaAz,
}

class CompraPipelinePendentesEstoqueScreen extends StatefulWidget {
  const CompraPipelinePendentesEstoqueScreen({super.key});

  @override
  State<CompraPipelinePendentesEstoqueScreen> createState() =>
      _CompraPipelinePendentesEstoqueScreenState();
}

class _CompraPipelinePendentesEstoqueScreenState
    extends State<CompraPipelinePendentesEstoqueScreen> {
  static const Color _primary = Color(0xFF6366F1);
  bool _carregando = true;
  String? _lojaId;
  /// precificado_pendente_estoque
  List<CompraItemPipeline> _listaProntosEstoque = const [];
  /// aguardando_precificacao (fluxo ativo; exclui cancelados por estado)
  List<CompraItemPipeline> _listaAguardandoPrecificacao = const [];
  /// concluido + compra cancelada depois
  List<CompraItemPipeline> _listaRastreio = const [];

  _FiltroHub _filtro = _FiltroHub.pendentes;
  _OrdenacaoHub _ordenacao = _OrdenacaoHub.recentes;

  final TextEditingController _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  /// Normaliza termo de busca (trim, minúsculas, sem acento).
  String _normalizarTermoBusca(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    return removeDiacritics(t.toLowerCase());
  }

  String get _qBuscaNormalizado => _normalizarTermoBusca(_buscaCtrl.text);

  bool get _buscaAtiva => _qBuscaNormalizado.isNotEmpty;

  List<CompraItemPipeline> _filtrarPorBusca(List<CompraItemPipeline> src) {
    final q = _qBuscaNormalizado;
    if (q.isEmpty) return src;
    return src.where((row) {
      final f = _normalizarTermoBusca(row.fornecedorNome);
      final r = _normalizarTermoBusca(row.referenciaCompra);
      return f.contains(q) || r.contains(q);
    }).toList();
  }

  int _cmpFornecedorAz(CompraItemPipeline a, CompraItemPipeline b) {
    final ca = _normalizarTermoBusca(a.fornecedorNome);
    final cb = _normalizarTermoBusca(b.fornecedorNome);
    final c = ca.compareTo(cb);
    if (c != 0) return c;
    final ra = _normalizarTermoBusca(a.referenciaCompra);
    final rb = _normalizarTermoBusca(b.referenciaCompra);
    final c2 = ra.compareTo(rb);
    if (c2 != 0) return c2;
    return a.id.compareTo(b.id);
  }

  int _cmpReferenciaAz(CompraItemPipeline a, CompraItemPipeline b) {
    final ra = _normalizarTermoBusca(a.referenciaCompra);
    final rb = _normalizarTermoBusca(b.referenciaCompra);
    final c = ra.compareTo(rb);
    if (c != 0) return c;
    return _cmpFornecedorAz(a, b);
  }

  /// Ordenação apenas em memória, após filtro + busca (não muta listas-base).
  List<CompraItemPipeline> _ordenarLista(List<CompraItemPipeline> src) {
    final copy = List<CompraItemPipeline>.from(src);
    switch (_ordenacao) {
      case _OrdenacaoHub.recentes:
        copy.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
        break;
      case _OrdenacaoHub.fornecedorAz:
        copy.sort(_cmpFornecedorAz);
        break;
      case _OrdenacaoHub.referenciaAz:
        copy.sort(_cmpReferenciaAz);
        break;
    }
    return copy;
  }

  /// Há itens no subconjunto do filtro atual após aplicar a busca.
  bool _existeConteudoFiltrado() {
    final mostrarAguardando =
        _filtro == _FiltroHub.pendentes || _filtro == _FiltroHub.todos;
    final mostrarProntos =
        _filtro == _FiltroHub.pendentes || _filtro == _FiltroHub.todos;
    final mostrarRastreio =
        _filtro == _FiltroHub.rastreio || _filtro == _FiltroHub.todos;
    final ag = mostrarAguardando
        ? _ordenarLista(_filtrarPorBusca(_listaAguardandoPrecificacao))
        : const <CompraItemPipeline>[];
    final pr = mostrarProntos
        ? _ordenarLista(_filtrarPorBusca(_listaProntosEstoque))
        : const <CompraItemPipeline>[];
    final rs = mostrarRastreio
        ? _ordenarLista(_filtrarPorBusca(_listaRastreio))
        : const <CompraItemPipeline>[];
    return ag.isNotEmpty || pr.isNotEmpty || rs.isNotEmpty;
  }

  Widget _buildCampoBusca(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _buscaCtrl,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar fornecedor ou referência',
        prefixIcon: const Icon(Icons.search, size: 22),
        suffixIcon: _buscaAtiva
            ? IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  _buscaCtrl.clear();
                  setState(() {});
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildOrdenacaoDropdown(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Ordenar',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_OrdenacaoHub>(
          value: _ordenacao,
          isDense: true,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: _OrdenacaoHub.recentes,
              child: Text('Mais recentes'),
            ),
            DropdownMenuItem(
              value: _OrdenacaoHub.fornecedorAz,
              child: Text('Fornecedor (A–Z)'),
            ),
            DropdownMenuItem(
              value: _OrdenacaoHub.referenciaAz,
              child: Text('Referência (A–Z)'),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _ordenacao = v);
          },
        ),
      ),
    );
  }

  Widget _buildBuscaEOrdenacao(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCampoBusca(context),
        const SizedBox(height: 10),
        _buildOrdenacaoDropdown(context),
      ],
    );
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (!mounted) return;
    if (lojaId == null || lojaId.isEmpty) {
      setState(() {
        _lojaId = null;
        _listaProntosEstoque = [];
        _listaAguardandoPrecificacao = [];
        _listaRastreio = [];
        _carregando = false;
      });
      return;
    }
    _lojaId = lojaId;
    final box = await CompraItemPipelineStore.openBox(lojaId);
    final prontos = <CompraItemPipeline>[];
    final aguardando = <CompraItemPipeline>[];
    final rastreio = <CompraItemPipeline>[];
    if (box != null) {
      for (final p in box.values) {
        if (p.lojaId != lojaId) continue;
        if (p.estado == CompraItemPipelineEstado.cancelado) continue;
        if (p.estado == CompraItemPipelineEstado.precificadoPendenteEstoque) {
          prontos.add(p);
        } else if (p.estado ==
            CompraItemPipelineEstado.aguardandoPrecificacao) {
          aguardando.add(p);
        } else if (compraPipelineDeveExibirOrigemCancelada(p)) {
          rastreio.add(p);
        }
      }
      prontos.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
      aguardando.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
      rastreio.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
    }
    setState(() {
      _listaProntosEstoque = prontos;
      _listaAguardandoPrecificacao = aguardando;
      _listaRastreio = rastreio;
      _carregando = false;
    });
  }

  int get _cntAguardando => _listaAguardandoPrecificacao.length;
  int get _cntProntos => _listaProntosEstoque.length;
  int get _cntRastreio => _listaRastreio.length;

  String _fmtMoney(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v);

  Produto? _produtoPorIdFirebase(Box<Produto> box, String fid) {
    final f = fid.trim();
    if (f.isEmpty) return null;
    for (final k in box.keys) {
      final p = box.get(k);
      if (p != null && p.idFirebase.trim() == f) return p;
    }
    return null;
  }

  Produto? _produtoParaRastreio(CompraItemPipeline row, Box<Produto> pBox) {
    final hk = row.produtoHiveKey;
    if (hk != null) {
      final p = pBox.get(hk);
      if (p != null) return p;
    }
    final fid = row.produtoIdFirebaseGravado.trim();
    if (fid.isNotEmpty) return _produtoPorIdFirebase(pBox, fid);
    return null;
  }

  Future<void> _abrirPrecificacao() async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const PrecificacaoUniversalScreen(),
      ),
    );
    if (mounted) await _carregar();
  }

  Future<void> _abrirProdutoRastreio(CompraItemPipeline row) async {
    final lid = _lojaId;
    if (lid == null) return;
    final name = HiveBoxNames.produtos(lid);
    final Box<Produto> pBox = Hive.isBoxOpen(name)
        ? Hive.box<Produto>(name)
        : await Hive.openBox<Produto>(name);
    final prod = _produtoParaRastreio(row, pBox);
    if (!mounted) return;
    if (prod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produto vinculado não encontrado neste aparelho.'),
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProdutoFormScreen(produto: prod),
      ),
    );
  }

  /// Indica se há referência local para abrir o cadastro (pode ainda falhar se o box não tiver o produto).
  bool _temReferenciaProdutoRastreio(CompraItemPipeline row) {
    if (row.produtoHiveKey != null) return true;
    return row.produtoIdFirebaseGravado.trim().isNotEmpty;
  }

  Future<void> _abrirFinalizacao(CompraItemPipeline row) async {
    final lid = _lojaId;
    if (lid == null) return;
    final name = HiveBoxNames.produtos(lid);
    final Box<Produto> pBox = Hive.isBoxOpen(name)
        ? Hive.box<Produto>(name)
        : await Hive.openBox<Produto>(name);

    final fid = row.productIdFirebase?.trim() ?? '';
    final existente =
        fid.isNotEmpty ? _produtoPorIdFirebase(pBox, fid) : null;

    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProdutoFormScreen(
          produto: existente,
          compraPipelineDocId: row.id,
        ),
      ),
    );
    if (mounted) await _carregar();
  }

  Widget _buildResumoCards(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget mini(String rotulo, int n, Color accent) {
      return Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rotulo,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mini('Aguardando\nprecificação', _cntAguardando, cs.primary),
        const SizedBox(width: 8),
        mini('Prontos no\nestoque', _cntProntos, const Color(0xFF059669)),
        const SizedBox(width: 8),
        mini('Rastreio', _cntRastreio, cs.tertiary),
      ],
    );
  }

  Widget _buildFiltros(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget filtroChip(String label, _FiltroHub valor) {
      final sel = _filtro == valor;
      return FilterChip(
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: cs.primaryContainer.withValues(alpha: 0.65),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
          color: sel ? cs.onPrimaryContainer : cs.onSurface,
        ),
        onSelected: (_) => setState(() => _filtro = valor),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exibir',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            filtroChip('Pendentes', _FiltroHub.pendentes),
            filtroChip('Rastreio', _FiltroHub.rastreio),
            filtroChip('Todos', _FiltroHub.todos),
          ],
        ),
      ],
    );
  }

  Widget _acaoRapida({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
        ),
      ),
    );
  }

  Widget _cardAguardandoPrecificacao(CompraItemPipeline row) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _abrirPrecificacao,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.nomeProdutoProvisorio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                row.fornecedorNome,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Aguardando precificação · Qtd ${row.quantidade} · '
                'Custo ${_fmtMoney(row.custoUnitario)}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _acaoRapida(
                label: 'Precificar',
                icon: Icons.calculate_outlined,
                onPressed: _abrirPrecificacao,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardProntoEstoque(CompraItemPipeline row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirFinalizacao(row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.nomeProdutoProvisorio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                row.fornecedorNome,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Pronto no estoque · Qtd ${row.quantidade} · '
                'Custo ${_fmtMoney(row.custoUnitario)} · '
                'Venda ${_fmtMoney(row.precoFinal)}',
                style: const TextStyle(fontSize: 12, height: 1.25),
              ),
              _acaoRapida(
                label: 'Finalizar',
                icon: Icons.inventory_2_outlined,
                onPressed: () => _abrirFinalizacao(row),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardRastreio(CompraItemPipeline row) {
    final temRef = _temReferenciaProdutoRastreio(row);
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: temRef ? () => _abrirProdutoRastreio(row) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.nomeProdutoProvisorio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    row.fornecedorNome,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const CompraPipelineOrigemCanceladaChip(),
                ],
              ),
              if (temRef)
                _acaoRapida(
                  label: 'Ver produto',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => _abrirProdutoRastreio(row),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    'Sem vínculo de produto neste aparelho.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _conteudoLista() {
    final out = <Widget>[];

    final agVis =
        _ordenarLista(_filtrarPorBusca(_listaAguardandoPrecificacao));
    final prVis = _ordenarLista(_filtrarPorBusca(_listaProntosEstoque));
    final rasVis = _ordenarLista(_filtrarPorBusca(_listaRastreio));

    final mostrarAguardando = _filtro == _FiltroHub.pendentes ||
        _filtro == _FiltroHub.todos;
    final mostrarProntos = _filtro == _FiltroHub.pendentes ||
        _filtro == _FiltroHub.todos;
    final mostrarRastreio =
        _filtro == _FiltroHub.rastreio || _filtro == _FiltroHub.todos;

    final doisBlocosOperacionais =
        agVis.isNotEmpty && prVis.isNotEmpty;

    if (mostrarAguardando && agVis.isNotEmpty) {
      if (_filtro == _FiltroHub.todos ||
          (_filtro == _FiltroHub.pendentes && doisBlocosOperacionais)) {
        out.add(_secaoTitulo('Aguardando precificação'));
        out.add(const SizedBox(height: 8));
      }
      for (final row in agVis) {
        out.add(_cardAguardandoPrecificacao(row));
      }
    }

    if (mostrarProntos && prVis.isNotEmpty) {
      if (_filtro == _FiltroHub.todos ||
          (_filtro == _FiltroHub.pendentes && doisBlocosOperacionais)) {
        if (out.isNotEmpty) out.add(const SizedBox(height: 8));
        out.add(_secaoTitulo('Prontos no estoque'));
        out.add(const SizedBox(height: 8));
      }
      for (final row in prVis) {
        out.add(_cardProntoEstoque(row));
      }
    }

    if (mostrarRastreio && rasVis.isNotEmpty) {
      if (_filtro == _FiltroHub.todos || _filtro == _FiltroHub.rastreio) {
        if (out.isNotEmpty) out.add(const SizedBox(height: 16));
        out.add(_secaoTitulo('Rastreio'));
        out.add(const SizedBox(height: 4));
        out.add(
          Text(
            'Concluídos no estoque; compra cancelada depois.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
        );
        out.add(const SizedBox(height: 12));
      }
      for (final row in rasVis) {
        out.add(_cardRastreio(row));
      }
    }

    return out;
  }

  Widget _secaoTitulo(String t) {
    return Text(
      t,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  bool get _nadaNoFiltro {
    switch (_filtro) {
      case _FiltroHub.pendentes:
        return _listaAguardandoPrecificacao.isEmpty &&
            _listaProntosEstoque.isEmpty;
      case _FiltroHub.rastreio:
        return _listaRastreio.isEmpty;
      case _FiltroHub.todos:
        return _listaAguardandoPrecificacao.isEmpty &&
            _listaProntosEstoque.isEmpty &&
            _listaRastreio.isEmpty;
    }
  }

  bool get _hubTotalmenteVazio =>
      _cntAguardando == 0 && _cntProntos == 0 && _cntRastreio == 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalizar compras no estoque'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : _carregar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _lojaId == null
              ? const Center(child: Text('Loja não encontrada.'))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: _hubTotalmenteVazio
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildResumoCards(context),
                            const SizedBox(height: 20),
                            _buildFiltros(context),
                            const SizedBox(height: 12),
                            _buildBuscaEOrdenacao(context),
                            const SizedBox(height: 32),
                            const Icon(Icons.inventory_2_outlined,
                                size: 56, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'Nada no pipeline desta loja.\n'
                                  'Confirme uma compra para ver itens aqui.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildResumoCards(context),
                            const SizedBox(height: 16),
                            _buildFiltros(context),
                            const SizedBox(height: 12),
                            _buildBuscaEOrdenacao(context),
                            const SizedBox(height: 20),
                            if (_nadaNoFiltro) ...[
                              Icon(
                                Icons.filter_alt_off_outlined,
                                size: 48,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _filtro == _FiltroHub.pendentes
                                    ? 'Nenhum item pendente no fluxo (precificação ou estoque).\n'
                                        'Use o filtro Rastreio ou Todos se precisar.'
                                    : _filtro == _FiltroHub.rastreio
                                        ? 'Nenhum item em rastreio.\n'
                                            'Use Pendentes ou Todos.'
                                        : 'Nada a exibir.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ] else if (!_existeConteudoFiltrado()) ...[
                              Icon(
                                Icons.search_off_outlined,
                                size: 48,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum item corresponde à busca.\n'
                                'Limpe o campo ou ajuste fornecedor / referência.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ] else
                              ..._conteudoLista(),
                          ],
                        ),
                ),
    );
  }
}
