// lib/screens/compras/fornecedor_compras_screen.dart
// Fase 1: histórico e resumo de compras por fornecedor (Hive local).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/compra_fornecedor.dart';
import '../../models/compra_fornecedor_constants.dart';
import '../../models/fornecedor.dart';
import '../../services/compra_fornecedor_hive_store.dart';
import '../../services/compra_fornecedor_sync_service.dart';
import 'compra_fornecedor_form_screen.dart';
import 'compras_revenda_pendentes_screen.dart';

class FornecedorComprasScreen extends StatefulWidget {
  const FornecedorComprasScreen({
    super.key,
    required this.lojaId,
    required this.fornecedorHiveKey,
    required this.fornecedor,
  });

  final String lojaId;
  final int fornecedorHiveKey;
  final Fornecedor fornecedor;

  @override
  State<FornecedorComprasScreen> createState() => _FornecedorComprasScreenState();
}

class _FornecedorComprasScreenState extends State<FornecedorComprasScreen> {
  static const Color _primary = Color(0xFF6366F1);
  static const Color _surface = Color(0xFFF8FAFC);

  bool _carregando = true;
  bool _syncing = false;
  List<CompraFornecedor> _lista = const [];

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() => _carregando = true);
    final box = await CompraFornecedorHiveStore.openBox(widget.lojaId);
    if (!mounted) return;
    if (box == null) {
      setState(() {
        _lista = [];
        _carregando = false;
      });
      return;
    }
    final lid = widget.lojaId.trim();
    final fk = widget.fornecedorHiveKey;
    final list = box.values
        .where((c) => c.lojaId == lid && c.fornecedorHiveKey == fk)
        .toList()
      ..sort((a, b) => b.dataCompra.compareTo(a.dataCompra));
    setState(() {
      _lista = list;
      _carregando = false;
    });
  }

  String _fmtMoney(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v);

  /// Compras deste fornecedor (lista atual) com sync pendente ou erro.
  int get _pendenciasSyncCount =>
      _lista.where(CompraFornecedorSyncService.precisaRetry).length;

  ({double totalComprado, double emAberto, DateTime? ultima}) _resumo() {
    double total = 0, aberto = 0;
    DateTime? ultima;
    for (final c in _lista) {
      if (c.statusCompra != CompraFornecedorStatusCompra.confirmada) continue;
      total += c.valorTotal;
      if (c.statusPagamento != CompraFornecedorStatusPagamento.pago) {
        aberto += c.valorEmAberto;
      }
      ultima = ultima == null || c.dataCompra.isAfter(ultima) ? c.dataCompra : ultima;
    }
    return (totalComprado: total, emAberto: aberto, ultima: ultima);
  }

  Future<void> _abrirNovaOuEditar(CompraFornecedor? existente) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CompraFornecedorFormScreen(
          lojaId: widget.lojaId,
          fornecedorHiveKey: widget.fornecedorHiveKey,
          fornecedorNome: widget.fornecedor.nome,
          compraExistente: existente,
        ),
      ),
    );
    if (mounted) await _recarregar();
  }

  Future<void> _sincronizarPendentes() async {
    if (_syncing) return;
    if (_pendenciasSyncCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma pendência para sincronizar'),
        ),
      );
      return;
    }
    setState(() => _syncing = true);
    try {
      final r =
          await CompraFornecedorSyncService.sincronizarTodasPendentesOuErro(
        widget.lojaId,
        fornecedorHiveKey: widget.fornecedorHiveKey,
      );
      if (!mounted) return;
      await _recarregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Este fornecedor — sincronizadas: ${r.sucesso} · falhas: ${r.falha}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _resumo();
    final fmtData = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: Text(
          'Compras · ${widget.fornecedor.nome}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Compras aguardando produtos',
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ComprasRevendaPendentesScreen(lojaId: widget.lojaId),
                ),
              );
            },
            icon: const Icon(Icons.playlist_add_check_outlined),
          ),
          if (!_carregando)
            Badge(
              isLabelVisible: _pendenciasSyncCount > 0,
              backgroundColor: Colors.deepOrange.shade600,
              label: Text(
                '$_pendenciasSyncCount',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              child: IconButton(
                tooltip: 'Sincronizar pendentes deste fornecedor',
                onPressed: _syncing ? null : _sincronizarPendentes,
                icon: _syncing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.cloud_upload_outlined,
                        color: _pendenciasSyncCount > 0
                            ? Colors.deepOrange
                            : Colors.white,
                      ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirNovaOuEditar(null),
        backgroundColor: _primary,
        icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
        label: const Text('Nova compra', style: TextStyle(color: Colors.white)),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _recarregar,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Resumo',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _ResumoCard(
                                  titulo: 'Total confirmado',
                                  valor: _fmtMoney(r.totalComprado),
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ResumoCard(
                                  titulo: 'Em aberto',
                                  valor: _fmtMoney(r.emAberto),
                                  icon: Icons.schedule,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _ResumoCard(
                            titulo: 'Última compra',
                            valor: r.ultima != null ? fmtData.format(r.ultima!) : '—',
                            icon: Icons.event,
                            isText: true,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Lançamentos',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  if (_lista.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 56, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhuma compra registrada',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Use “Nova compra” para criar um rascunho ou confirmar uma compra.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final c = _lista[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                elevation: 0,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _abrirNovaOuEditar(c),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c.referenciaInterna.isEmpty
                                                    ? 'Sem referência'
                                                    : c.referenciaInterna,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            _ChipStatus(
                                              label: CompraFornecedorStatusCompra.legivel(
                                                  c.statusCompra),
                                              cor: _corStatusCompra(c.statusCompra),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          fmtData.format(c.dataCompra),
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _fmtMoney(c.valorTotal),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 17,
                                                color: _primary,
                                              ),
                                            ),
                                            _ChipStatus(
                                              label:
                                                  CompraFornecedorStatusPagamento.legivel(
                                                      c.statusPagamento),
                                              cor: _corStatusPagamento(c.statusPagamento),
                                            ),
                                          ],
                                        ),
                                        if (c.statusCompra ==
                                                CompraFornecedorStatusCompra.confirmada &&
                                            c.valorEmAberto > 0.009) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Aberto: ${_fmtMoney(c.valorEmAberto)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange[800],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: _lista.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              ),
            ),
    );
  }

  Color _corStatusCompra(String s) {
    switch (s) {
      case CompraFornecedorStatusCompra.confirmada:
        return Colors.green.shade700;
      case CompraFornecedorStatusCompra.cancelada:
        return Colors.red.shade700;
      default:
        return Colors.blueGrey.shade600;
    }
  }

  Color _corStatusPagamento(String s) {
    switch (s) {
      case CompraFornecedorStatusPagamento.pago:
        return Colors.green.shade700;
      case CompraFornecedorStatusPagamento.parcial:
        return Colors.orange.shade800;
      default:
        return Colors.blueGrey.shade600;
    }
  }
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.icon,
    this.isText = false,
  });

  final String titulo;
  final String valor;
  final IconData icon;
  final bool isText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF6366F1)),
          const SizedBox(height: 8),
          Text(
            titulo,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isText ? 15 : 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipStatus extends StatelessWidget {
  const _ChipStatus({required this.label, required this.cor});

  final String label;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cor,
        ),
      ),
    );
  }
}
