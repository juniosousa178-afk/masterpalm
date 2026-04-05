// lib/screens/financeiro/financeiro_screen.dart
// Hub do módulo financeiro (complementar ao restante do app).

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../core/hive_box_names.dart';
import '../../models/lancamento_financeiro.dart';
import '../../models/venda.dart';
import '../../services/fechamento_service.dart';
import '../../services/financeiro_firestore_service.dart';
import '../../services/financeiro_hive_store.dart';
import '../../services/financeiro_service.dart';
import '../../services/loja_id_service.dart';
import '../../utils/role_utils.dart';
import '../relatorio_financeiro_screen.dart';
import '../relatorios_financeiros_screen.dart';
import 'financeiro_lancamentos_screen.dart';
import 'gastos_fixos_screen.dart';

class FinanceiroScreen extends StatefulWidget {
  const FinanceiroScreen({super.key});

  @override
  State<FinanceiroScreen> createState() => _FinanceiroScreenState();
}

class _FinanceiroScreenState extends State<FinanceiroScreen> {
  static const Color _primary = Color(0xFF6366F1);
  static const Color _success = Color(0xFF22C55E);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _muted = Color(0xFF64748B);

  bool _loading = true;
  bool _acessoNegado = false;
  String? _erro;
  String _lojaId = '';
  Box<LancamentoFinanceiro>? _lancBox;

  ResumoFinanceiroModulo _moduloMes = const ResumoFinanceiroModulo();
  ({
    double venda,
    double custo,
    double taxas,
    double lucro,
    double dinheiro,
    double pix,
    double cartao
  })? _resumoVendasMes;

  /// Última migração F2C (Hive→Firestore) — informativo; não bloqueia reexecução.
  FinanceiroMigracaoF2cRegistroLeitura? _ultimaMigrF2c;
  /// Último pull F2D (Firestore→Hive) — informativo.
  FinanceiroPullF2dRegistroLeitura? _ultimaPullF2d;
  bool _migrando = false;
  bool _pullando = false;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
      _acessoNegado = false;
    });
    try {
      final role = await RoleUtils.loadFromSession();
      if (!mounted) return;
      if (!role.canViewGlobalFinancials) {
        setState(() {
          _loading = false;
          _acessoNegado = true;
        });
        return;
      }

      final id = (await LojaIdService.getWithTimeout(
                  timeout: const Duration(seconds: 10)))
              ?.trim() ??
          '';
      if (!mounted) return;
      if (id.isEmpty) {
        throw Exception('Loja não encontrada.');
      }
      _lojaId = id;
      _lancBox = await FinanceiroHiveStore.openLancamentosBox(id);

      final now = DateTime.now();
      if (_lancBox != null) {
        _moduloMes = FinanceiroService.resumoMesCalendario(
          box: _lancBox!,
          lojaId: id,
          ano: now.year,
          mes: now.month,
        );
      } else {
        _moduloMes = const ResumoFinanceiroModulo();
      }

      _resumoVendasMes = null;
      try {
        final vendasName = HiveBoxNames.vendas(id);
        final vendasBox = Hive.isBoxOpen(vendasName)
            ? Hive.box<Venda>(vendasName)
            : await Hive.openBox<Venda>(vendasName);
        _resumoVendasMes = await FechamentoService.resumoMes(
          ano: now.year,
          mes: now.month,
          lojaId: id,
          vendasBox: vendasBox,
        );
      } catch (_) {
        _resumoVendasMes = null;
      }

      FinanceiroMigracaoF2cRegistroLeitura? regMigr;
      try {
        regMigr = await FinanceiroFirestoreService.lerUltimaMigracaoF2c(id);
      } catch (_) {
        regMigr = null;
      }

      FinanceiroPullF2dRegistroLeitura? regPull;
      try {
        regPull = await FinanceiroFirestoreService.lerUltimaPullF2d(id);
      } catch (_) {
        regPull = null;
      }

      if (mounted) {
        setState(() {
          _ultimaMigrF2c = regMigr;
          _ultimaPullF2d = regPull;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.toString();
        });
      }
    }
  }

  String _textoUltimaMigracao(FinanceiroMigracaoF2cRegistroLeitura r) {
    final iso = r.executadoEmIso;
    String quando = '—';
    if (iso != null && iso.isNotEmpty) {
      try {
        final dt = DateTime.tryParse(iso);
        if (dt != null) {
          quando = DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal());
        }
      } catch (_) {}
    }
    final env = r.lancamentosEnviados + r.gastosEnviados;
    final pul = r.lancamentosPulados + r.gastosPulados;
    final err = r.lancamentosErros + r.gastosErros;
    return 'Última migração nuvem: $quando · enviados $env · já existiam $pul · erros $err';
  }

  String _textoUltimaPull(FinanceiroPullF2dRegistroLeitura r) {
    final iso = r.executadoEmIso;
    String quando = '—';
    if (iso != null && iso.isNotEmpty) {
      try {
        final dt = DateTime.tryParse(iso);
        if (dt != null) {
          quando = DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal());
        }
      } catch (_) {}
    }
    final imp = r.lancamentosImportados + r.gastosImportados;
    final pul = r.lancamentosPulados + r.gastosPulados;
    final err = r.lancamentosErros + r.gastosErros;
    return 'Última importação nuvem: $quando · novos $imp · já no aparelho $pul · erros $err';
  }

  Future<void> _confirmarEPullDaNuvem() async {
    if (!mounted || _lojaId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar da nuvem'),
        content: const Text(
          'Importar da nuvem apenas os registros que ainda não existem no aparelho. '
          'Nada local será apagado ou substituído.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _pullando = true);
    FinanceiroPullF2dResultado? resultado;
    try {
      resultado =
          await FinanceiroFirestoreService.pullLojaFirestoreParaHiveFase2d(
        _lojaId,
      );
    } catch (e) {
      resultado = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Importação falhou: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pullando = false);
    }

    if (!mounted) return;
    if (resultado != null && resultado.ignoradoJaEmExecucao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Importação já em andamento. Aguarde concluir.'),
        ),
      );
      return;
    }
    if (resultado == null) return;
    final r = resultado;

    await _load();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importação concluída'),
        content: SingleChildScrollView(
          child: Text(
            'Lançamentos: ${r.lancamentosImportados} importados, '
            '${r.lancamentosPulados} ignorados (já no aparelho), '
            '${r.lancamentosErros} erros.\n\n'
            'Gastos fixos: ${r.gastosImportados} importados, '
            '${r.gastosPulados} ignorados (já no aparelho), '
            '${r.gastosErros} erros.\n\n'
            'Total importado: ${r.totalImportados} · '
            'ignorados: ${r.totalPulados} · '
            'erros: ${r.totalErros}.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarEMigrarParaFirestore() async {
    if (!mounted || _lojaId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migração para nuvem'),
        content: const Text(
          'Serão enviados para o Firestore os lançamentos financeiros e gastos fixos '
          'desta loja que ainda não existirem na nuvem. Dados locais não serão '
          'alterados nem apagados. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Executar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _migrando = true);
    FinanceiroMigracaoF2cResultado? resultado;
    try {
      resultado =
          await FinanceiroFirestoreService.migrarLojaHiveParaFirestorePolicyA(
        _lojaId,
      );
    } catch (e) {
      resultado = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Migração interrompida: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _migrando = false);
    }

    if (!mounted || resultado == null) return;
    final r = resultado;

    FinanceiroMigracaoF2cRegistroLeitura? reg;
    try {
      reg = await FinanceiroFirestoreService.lerUltimaMigracaoF2c(_lojaId);
    } catch (_) {
      reg = null;
    }
    if (mounted) {
      setState(() => _ultimaMigrF2c = reg);
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migração concluída'),
        content: SingleChildScrollView(
          child: Text(
            'Lançamentos: ${r.lancamentosEnviados} enviados, '
            '${r.lancamentosPulados} ignorados (já na nuvem), '
            '${r.lancamentosErros} erros.\n\n'
            'Gastos fixos: ${r.gastosEnviados} enviados, '
            '${r.gastosPulados} ignorados (já na nuvem), '
            '${r.gastosErros} erros.\n\n'
            'Total enviado: ${r.totalEnviados} · '
            'pulados: ${r.totalPulados} · '
            'erros: ${r.totalErros}.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _voltarOuFechar() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed('/home');
    }
  }

  List<LancamentoFinanceiro> get _recentes {
    if (_lancBox == null || _lojaId.isEmpty) return [];
    final list = _lancBox!.values
        .where((l) => l.lojaId == _lojaId)
        .toList()
      ..sort((a, b) =>
          b.dataEfetivaPagamentoOuLancamento
              .compareTo(a.dataEfetivaPagamentoOuLancamento));
    return list.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Gestão financeira'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: (_loading ||
                    _migrando ||
                    _pullando ||
                    _lojaId.isEmpty ||
                    _acessoNegado ||
                    _erro != null)
                ? null
                : _confirmarEPullDaNuvem,
            tooltip: 'Importar da nuvem (só registros ausentes)',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: (_loading ||
                    _migrando ||
                    _pullando ||
                    _lojaId.isEmpty ||
                    _acessoNegado ||
                    _erro != null)
                ? null
                : _confirmarEMigrarParaFirestore,
            tooltip: 'Enviar dados locais para nuvem (migração)',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _acessoNegado
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 56, color: Colors.grey.shade600),
                        const SizedBox(height: 16),
                        const Text(
                          'Acesso restrito',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A gestão financeira está disponível apenas para administradores.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _voltarOuFechar,
                          child: const Text('Voltar'),
                        ),
                      ],
                    ),
                  ),
                )
              : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_erro!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _muted)),
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
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Resumo do mês (${DateFormat.MMMM('pt_BR').format(DateTime.now())})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                      if (_ultimaMigrF2c != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _textoUltimaMigracao(_ultimaMigrF2c!),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      if (_ultimaPullF2d != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _textoUltimaPull(_ultimaPullF2d!),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _cardResumo(),
                      const SizedBox(height: 8),
                      Text(
                        'Os valores de vendas abaixo seguem o mesmo critério do relatório financeiro. Lançamentos do módulo são complementares.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _chipAcao(
                            icon: Icons.add_circle_outline,
                            label: 'Novo lançamento',
                            onTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FinanceiroLancamentosScreen(
                                    lojaId: _lojaId,
                                  ),
                                ),
                              );
                              if (!mounted) return;
                              _load();
                            },
                          ),
                          _chipAcao(
                            icon: Icons.event_repeat,
                            label: 'Gastos fixos',
                            onTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GastosFixosScreen(lojaId: _lojaId),
                                ),
                              );
                              if (!mounted) return;
                              _load();
                            },
                          ),
                          _chipAcao(
                            icon: Icons.calendar_month,
                            label: 'Fechamento',
                            onTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const RelatorioFinanceiroScreen(),
                                ),
                              );
                            },
                          ),
                          _chipAcao(
                            icon: Icons.insights,
                            label: 'Relatórios e metas',
                            onTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const RelatoriosFinanceirosScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Lançamentos recentes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FinanceiroLancamentosScreen(
                                    lojaId: _lojaId,
                                  ),
                                ),
                              );
                              if (!mounted) return;
                              _load();
                            },
                            child: const Text('Ver todos'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_recentes.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Nenhum lançamento nesta loja. Toque em "Novo lançamento" para começar.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        )
                      else
                        ..._recentes.map(_tileLancamento),
                    ],
                  ),
                ),
    );
  }

  Widget _cardResumo() {
    final rv = _resumoVendasMes;
    final lucroVendas = rv?.lucro;
    final lucroComModulo = lucroVendas != null
        ? FinanceiroService.lucroEstimadoComModulo(
            lucroVendasTaxasCustos: lucroVendas,
            modulo: _moduloMes,
          )
        : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (rv != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _miniMetric(
                      'Vendas (mês)',
                      _moeda.format(rv.venda),
                      _primary,
                    ),
                  ),
                  Expanded(
                    child: _miniMetric(
                      'Lucro operacional*',
                      _moeda.format(rv.lucro),
                      _success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Entradas extras',
                    _moeda.format(_moduloMes.totalEntradasExtras),
                    _success,
                  ),
                ),
                Expanded(
                  child: _miniMetric(
                    'Despesas (módulo)',
                    _moeda.format(_moduloMes.totalSaidasExplicitas),
                    _warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Investimentos',
                    _moeda.format(_moduloMes.totalInvestimentos),
                    Colors.deepPurple,
                  ),
                ),
                Expanded(
                  child: _miniMetric(
                    'Resultado ajustado**',
                    _moeda.format(
                      lucroComModulo ??
                          _moduloMes.impactoLiquidoModulo,
                    ),
                    lucroComModulo != null && lucroComModulo >= 0
                        ? _success
                        : Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '* Lucro operacional de vendas: total − custo − taxas (como no fechamento).\n'
              '** Vendas + impacto dos lançamentos do módulo no período (não é lucro líquido contábil).',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipAcao({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: _primary),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileLancamento(LancamentoFinanceiro l) {
    final df = DateFormat('dd/MM/yy');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _primary.withValues(alpha: 0.12),
          child: const Icon(Icons.receipt_long,
              color: Color(0xFF6366F1), size: 20),
        ),
        title: Text(
          l.descricao.isEmpty ? '(sem descrição)' : l.descricao,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${df.format(l.dataEfetivaPagamentoOuLancamento)} · ${l.status}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Text(
          _moeda.format(l.valor),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
