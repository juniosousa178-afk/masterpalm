// lib/screens/financeiro/financeiro_resumo_consolidado_screen.dart
// Visão consolidada: lucro operacional de vendas, resultado gerencial e fluxo de caixa.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/hive_box_names.dart';
import '../../models/venda.dart';
import '../../services/fechamento_service.dart';
import '../../services/financeiro_hive_store.dart';
import '../../services/financeiro_service.dart';

/// Resumo por mês civil (mesma base da gestão financeira).
class FinanceiroResumoConsolidadoScreen extends StatefulWidget {
  const FinanceiroResumoConsolidadoScreen({
    super.key,
    required this.lojaId,
    this.mesInicial,
  });

  final String lojaId;

  /// `null` ao abrir isolado: mês civil atual. Com valor: continua o fluxo (ex.: vindo da gestão).
  final DateTime? mesInicial;

  @override
  State<FinanceiroResumoConsolidadoScreen> createState() =>
      _FinanceiroResumoConsolidadoScreenState();
}

class _FinanceiroResumoConsolidadoScreenState
    extends State<FinanceiroResumoConsolidadoScreen> {
  static const Color _primary = Color(0xFF6366F1);
  static const Color _success = Color(0xFF22C55E);
  static const Color _muted = Color(0xFF64748B);

  late DateTime _mesRef;

  bool _loading = true;
  String? _erro;
  ResumoFinanceiroModulo _modulo = const ResumoFinanceiroModulo();
  ({
    double venda,
    double custo,
    double taxas,
    double lucro,
    double dinheiro,
    double pix,
    double cartao
  })? _vendasMes;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  @override
  void initState() {
    super.initState();
    final w = widget.mesInicial;
    _mesRef = w != null
        ? DateTime(w.year, w.month)
        : DateTime(DateTime.now().year, DateTime.now().month);
    _load();
  }

  bool _mesmoMesCivil(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  void _mudarMes(int delta) {
    final n = DateTime(_mesRef.year, _mesRef.month + delta);
    final next = DateTime(n.year, n.month);
    setState(() => _mesRef = next);
    _load();
  }

  void _irParaMesAtual() {
    final alvo = DateTime(DateTime.now().year, DateTime.now().month);
    if (_mesmoMesCivil(_mesRef, alvo)) return;
    setState(() => _mesRef = alvo);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final id = widget.lojaId.trim();
      if (id.isEmpty) throw Exception('Loja inválida.');

      final lancBox = await FinanceiroHiveStore.openLancamentosBox(id);
      final y = _mesRef.year;
      final m = _mesRef.month;
      ResumoFinanceiroModulo modulo = const ResumoFinanceiroModulo();
      if (lancBox != null) {
        modulo = FinanceiroService.resumoMesCalendario(
          box: lancBox,
          lojaId: id,
          ano: y,
          mes: m,
        );
      }

      ({
        double venda,
        double custo,
        double taxas,
        double lucro,
        double dinheiro,
        double pix,
        double cartao
      })? rv;
      try {
        final vendasName = HiveBoxNames.vendas(id);
        final vendasBox = Hive.isBoxOpen(vendasName)
            ? Hive.box<Venda>(vendasName)
            : await Hive.openBox<Venda>(vendasName);
        rv = await FechamentoService.resumoMes(
          ano: y,
          mes: m,
          lojaId: id,
          vendasBox: vendasBox,
        );
      } catch (_) {
        rv = null;
      }

      if (!mounted) return;
      setState(() {
        _modulo = modulo;
        _vendasMes = rv;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.toString();
        });
      }
    }
  }

  Future<void> _compartilharResumo({
    required double lucroOp,
    required double resultado,
    required double fluxo,
  }) async {
    final periodo = DateFormat.yMMMM('pt_BR').format(_mesRef);
    final buf = StringBuffer()
      ..writeln('MasterPalm — Resumo financeiro')
      ..writeln('Período: $periodo')
      ..writeln('')
      ..writeln('Lucro operacional de vendas: ${_moeda.format(lucroOp)}')
      ..writeln('Resultado gerencial: ${_moeda.format(resultado)}')
      ..writeln('Fluxo de caixa: ${_moeda.format(fluxo)}');
    await SharePlus.instance.share(
      ShareParams(
        text: buf.toString(),
        subject: 'Resumo financeiro $periodo',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rv = _vendasMes;
    final lucroOp = rv?.lucro ?? 0.0;
    final resultado = FinanceiroService.resultadoGerencialComModulo(
      lucroOperacionalVendas: lucroOp,
      modulo: _modulo,
    );
    final somaFormas = rv != null ? rv.dinheiro + rv.pix + rv.cartao : 0.0;
    final fluxo = FinanceiroService.fluxoCaixaComVendas(
      somaFormasPagamentoVendas: somaFormas,
      modulo: _modulo,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Resumo financeiro consolidado'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Compartilhar texto',
            icon: const Icon(Icons.share_outlined),
            onPressed: _loading
                ? null
                : () => _compartilharResumo(
                      lucroOp: lucroOp,
                      resultado: resultado,
                      fluxo: fluxo,
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _primary,
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => _mudarMes(-1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Expanded(
                                  child: Text(
                                    DateFormat.yMMMM('pt_BR').format(_mesRef),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: _muted,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _mudarMes(1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                            if (!_mesmoMesCivil(
                              _mesRef,
                              DateTime(
                                DateTime.now().year,
                                DateTime.now().month,
                              ),
                            ))
                              TextButton(
                                onPressed: _irParaMesAtual,
                                child: const Text('Mês atual'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed<void>(
                              context,
                              '/financeiro',
                              arguments: <String, dynamic>{
                                'mesInicial':
                                    DateTime(_mesRef.year, _mesRef.month),
                              },
                            );
                          },
                          icon: const Icon(Icons.account_balance_wallet_outlined),
                          label: const Text('Gestão financeira detalhada'),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                            label: const Text(
                              'KPIs do mês civil (por pagamento)',
                              style: TextStyle(fontSize: 11),
                            ),
                            avatar: const Icon(Icons.payments_outlined,
                                size: 16, color: _primary),
                            side: BorderSide(color: Colors.grey.shade300),
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Como ler estes números',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• Lucro operacional de vendas: só a operação comercial '
                                  '(receita − custo − taxas). Não inclui despesas manuais do módulo.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '• Resultado gerencial: lucro operacional menos tudo que o módulo '
                                  'considera como saída gerencial no período (fixos, variáveis, legado, equipe, etc.), '
                                  'com ajustes; não duplica compra de mercadoria.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '• Fluxo de caixa: movimento de dinheiro no período '
                                  '(formas de pagamento das vendas + lançamentos).',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '• Competência × pagamento: os valores desta tela seguem pagamentos efetivos '
                                  '(como os KPIs da gestão). A lista na gestão pode ser vista por competência '
                                  'para organização — isso não muda estes totais.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade800),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, c) {
                            final wide = c.maxWidth >= 520;
                            final cards = [
                              _CardGrande(
                                titulo: 'Lucro operacional de vendas',
                                valor: _moeda.format(lucroOp),
                                subtitulo: rv != null
                                    ? 'Vendas ${_moeda.format(rv.venda)} − custos − taxas'
                                    : 'Sem dados de vendas no período',
                                cor: _success,
                                icone: Icons.storefront_outlined,
                              ),
                              _CardGrande(
                                titulo: 'Resultado gerencial do mês',
                                valor: _moeda.format(resultado),
                                subtitulo:
                                    'Lucro op. − (fixos + variáveis + legado + equipe) + ajustes',
                                cor: resultado >= 0 ? _success : Colors.redAccent,
                                icone: Icons.account_balance_outlined,
                              ),
                              _CardGrande(
                                titulo: 'Fluxo de caixa do período',
                                valor: _moeda.format(fluxo),
                                subtitulo: rv != null
                                    ? 'Formas de pgto + lançamentos (todas as saídas e entradas)'
                                    : 'Sem vendas no período: fluxo só com lançamentos',
                                cor: fluxo >= 0 ? _primary : Colors.redAccent,
                                icone: Icons.payments_outlined,
                              ),
                            ];
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < cards.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 12),
                                    Expanded(child: cards[i]),
                                  ],
                                ],
                              );
                            }
                            return Column(
                              children: [
                                for (var i = 0; i < cards.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 12),
                                  cards[i],
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Composição do período (lançamentos pagos)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                _LinhaComp(
                                    'Gastos fixos pagos', _modulo.totalGastosFixos, _moeda),
                                _LinhaComp('Gastos variáveis pagos',
                                    _modulo.totalGastosVariaveis, _moeda),
                                _LinhaComp(
                                    'Despesa operacional (legado)',
                                    _modulo.totalDespesasOperacionais,
                                    _moeda),
                                const Divider(height: 1),
                                _LinhaComp('Equipe / pró-labore',
                                    _modulo.totalPagamentosEquipe, _moeda),
                                _LinhaComp('Compras de mercadoria',
                                    _modulo.totalCompraMercadoria, _moeda),
                                _LinhaComp(
                                    'Investimentos', _modulo.totalInvestimentos, _moeda),
                                _LinhaComp(
                                    'Retiradas', _modulo.totalRetiradas, _moeda),
                                _LinhaComp('Entradas extras', _modulo.totalEntradasExtras,
                                    _moeda,
                                    positivoEntrada: true),
                                _LinhaComp('Ajustes financeiros', _modulo.totalAjustes,
                                    _moeda,
                                    neutro: true),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Gastos fixos cadastrados: use “Gerar lançamentos” na tela de gastos fixos '
                          'ou lance manualmente. Sugestões ficam pendentes até pagas.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _CardGrande extends StatelessWidget {
  const _CardGrande({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.cor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final String subtitulo;
  final Color cor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              valor,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaComp extends StatelessWidget {
  const _LinhaComp(
    this.rotulo,
    this.valor,
    this.fmt, {
    this.positivoEntrada = false,
    this.neutro = false,
  });

  final String rotulo;
  final double valor;
  final NumberFormat fmt;
  final bool positivoEntrada;
  final bool neutro;

  @override
  Widget build(BuildContext context) {
    final cor = neutro
        ? Colors.grey.shade800
        : (positivoEntrada && valor > 0)
            ? const Color(0xFF22C55E)
            : Colors.grey.shade800;
    return ListTile(
      dense: true,
      title: Text(rotulo, style: const TextStyle(fontSize: 14)),
      trailing: Text(
        fmt.format(valor),
        style: TextStyle(fontWeight: FontWeight.w600, color: cor, fontSize: 14),
      ),
    );
  }
}
