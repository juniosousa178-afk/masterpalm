// lib/screens/financeiro/financeiro_screen.dart
// Hub do módulo financeiro (complementar ao restante do app).

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../core/hive_box_names.dart';
import '../../financeiro/financeiro_constants.dart';
import '../../financeiro/lancamento_financeiro_competencia_ui.dart';
import '../../financeiro/lancamento_financeiro_origem_ui.dart';
import '../../services/conta_receber_service.dart';
import '../../services/conta_pagar_hive_store.dart';
import '../../services/conta_pagar_service.dart';
import '../../models/conta_receber.dart';
import '../../models/lancamento_financeiro.dart';
import '../../models/venda.dart';
import '../../services/fechamento_service.dart';
import '../../services/financeiro_firestore_service.dart';
import '../../services/financeiro_hive_store.dart';
import '../../services/financeiro_pdf_service.dart';
import '../../core/financeiro_lancamento_acao.dart';
import '../../services/financeiro_lancamento_exclusao_service.dart';
import '../../services/financeiro_service.dart';
import '../../services/financeiro_ui_prefs_service.dart';
import '../../services/gasto_fixo_lancamento_service.dart';
import '../../services/loja_id_service.dart';
import '../../utils/role_utils.dart';
import '../relatorio_financeiro_screen.dart';
import '../relatorios_financeiros_screen.dart';
import '../contas_pagar_screen.dart';
import 'financeiro_lancamentos_screen.dart';
import 'controle_compras_fornecedor_screen.dart';
import 'financeiro_resumo_consolidado_screen.dart';
import 'gastos_fixos_screen.dart';
import '../../widgets/app_help_icon_button.dart';

class FinanceiroScreen extends StatefulWidget {
  const FinanceiroScreen({super.key, this.mesInicial});

  /// Quando aberto a partir do resumo consolidado: mantém o mês do fluxo atual.
  /// Cold start / rota nomeada: use `null` (sempre mês civil atual).
  final DateTime? mesInicial;

  @override
  State<FinanceiroScreen> createState() => _FinanceiroScreenState();
}

class _FinanceiroScreenState extends State<FinanceiroScreen> {
  static const Color _primary = Color(0xFF6366F1);
  static const Color _success = Color(0xFF22C55E);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _muted = Color(0xFF64748B);

  static const Color _error = Color(0xFFEF4444);

  late DateTime _mesSelecionado;

  bool _prefsCarregadasDoDisco = false;
  String? _prefsUserKeyCache;
  String? _filtroStatus; // null = todos; pago | pendente
  String? _filtroTipoGrupo; // null = todos; tipo ou [FinanceiroUiPrefsService.filtroGrupoEquipe]

  /// Lista abaixo: `false` = critério data efetiva (pagamento ou lançamento); `true` = competência.
  bool _visaoListaPorCompetencia = false;

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

  double _totalContasReceberPendentes = 0;
  ResumoContasPagar _resumoContasPagar = const ResumoContasPagar();
  String _nomeLojaExibicao = '';
  List<ContaReceber> _contasReceberCache = [];

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
    final w = widget.mesInicial;
    _mesSelecionado = w != null
        ? DateTime(w.year, w.month)
        : DateTime(DateTime.now().year, DateTime.now().month);
    _load();
  }

  bool _mesmoMesCivil(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  Future<void> _persistirUiPrefs() async {
    if (_lojaId.isEmpty) return;
    final uk = _prefsUserKeyCache ?? await FinanceiroUiPrefsService.resolveUserKey();
    _prefsUserKeyCache = uk;
    await FinanceiroUiPrefsService.save(
      visaoCompetencia: _visaoListaPorCompetencia,
      filtroStatus: _filtroStatus,
      filtroTipoGrupo: _filtroTipoGrupo,
      lojaId: _lojaId,
      userKey: uk,
    );
  }

  void _irParaMesAtual() {
    final alvo = DateTime(DateTime.now().year, DateTime.now().month);
    if (_mesmoMesCivil(_mesSelecionado, alvo)) return;
    setState(() => _mesSelecionado = alvo);
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

      final id = (await LojaIdService.getWithTimeoutThenSessionFallback(
                  timeout: const Duration(seconds: 10)))
              ?.trim() ??
          '';
      if (!mounted) return;
      if (id.isEmpty) {
        throw Exception('Loja não encontrada.');
      }
      final lojaAnterior = _lojaId;
      _lojaId = id;
      if (lojaAnterior.isNotEmpty && lojaAnterior != id) {
        _prefsCarregadasDoDisco = false;
      }

      if (!_prefsCarregadasDoDisco) {
        final userKey = await FinanceiroUiPrefsService.resolveUserKey();
        _prefsUserKeyCache = userKey;
        final d = await FinanceiroUiPrefsService.load(
          lojaId: id,
          userKey: userKey,
        );
        if (!mounted) return;
        setState(() {
          _visaoListaPorCompetencia = d.visaoCompetencia;
          _filtroStatus = d.filtroStatus;
          _filtroTipoGrupo = d.filtroTipoGrupo;
          _prefsCarregadasDoDisco = true;
        });
      }

      _lancBox = await FinanceiroHiveStore.openLancamentosBox(id);
      if (_lancBox == null) {
        debugPrint(
          '[FINANCEIRO_UI] openLancamentosBox retornou null (lojaId=$id). '
          'Resumo do módulo ficará zerado; lançamentos podem existir no disco.',
        );
      } else {
        try {
          final removidos =
              await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(
            id,
          );
          if (removidos > 0) {
            debugPrint(
              '[FIN-GESTAO][REFRESH-APOS-TOMBSTONE] removidos=$removidos lojaId=$id',
            );
          }
        } catch (e) {
          debugPrint(
            '[FIN-GESTAO][TOMBSTONE-ERRO] type=${e.runtimeType} lojaId=$id',
          );
        }
      }

      final y = _mesSelecionado.year;
      final m = _mesSelecionado.month;
      if (_lancBox != null) {
        _moduloMes = FinanceiroService.resumoMesCalendario(
          box: _lancBox!,
          lojaId: id,
          ano: y,
          mes: m,
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
          ano: y,
          mes: m,
          lojaId: id,
          vendasBox: vendasBox,
        );
      } catch (_) {
        _resumoVendasMes = null;
      }

      var nomeLojaUi = '';
      try {
        final cfg = Hive.isBoxOpen('config')
            ? Hive.box('config')
            : await Hive.openBox('config');
        nomeLojaUi = (cfg.get('store_name') ?? '').toString().trim();
      } catch (_) {}

      var totalCr = 0.0;
      var crCache = <ContaReceber>[];
      try {
        final crBox = await ContaReceberService.openBoxLoja(id);
        crCache = crBox.values.toList();
        for (final c in ContaReceberService.listar(
          contas: crBox.values,
          lojaId: id,
          filtro: 'pendentes',
        )) {
          totalCr += c.valor;
        }
      } catch (_) {}

      var resumoCp = const ResumoContasPagar();
      try {
        final cpBox = await ContaPagarHiveStore.openBox(id);
        if (cpBox != null) {
          final contas =
              cpBox.values.where((c) => c.lojaId == id).toList();
          resumoCp = ContaPagarService.resumo(
            contas: contas,
            ano: y,
            mes: m,
            visaoCompetencia: _visaoListaPorCompetencia,
          );
        }
      } catch (_) {}

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
          if (nomeLojaUi.isNotEmpty) {
            _nomeLojaExibicao = nomeLojaUi;
          }
          _totalContasReceberPendentes = totalCr;
          _contasReceberCache = crCache;
          _resumoContasPagar = resumoCp;
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
      await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(
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

  void _mudarMes(int delta) {
    final n = DateTime(_mesSelecionado.year, _mesSelecionado.month + delta);
    setState(() => _mesSelecionado = DateTime(n.year, n.month));
    _load();
  }

  bool _passaFiltroTipo(LancamentoFinanceiro l) {
    final g = _filtroTipoGrupo;
    if (g == null) return true;
    if (g == FinanceiroUiPrefsService.filtroGrupoEquipe) {
      return l.tipo == FinanceiroTipoLancamento.pagamentoFuncionario ||
          l.tipo == FinanceiroTipoLancamento.proLabore;
    }
    return l.tipo == g;
  }

  String _fmtMesAnoPt(DateTime d) =>
      DateFormat('MMM/yyyy', 'pt_BR').format(d);

  bool _entraListaPorPagamento(LancamentoFinanceiro l) {
    final ini = DateTime(_mesSelecionado.year, _mesSelecionado.month, 1);
    final fim = DateTime(
      _mesSelecionado.year,
      _mesSelecionado.month + 1,
      0,
      23,
      59,
      59,
      999,
    );
    final d = l.dataEfetivaPagamentoOuLancamento;
    return !d.isBefore(ini) && !d.isAfter(fim);
  }

  List<LancamentoFinanceiro> get _lancamentosFiltrados {
    if (_lancBox == null || _lojaId.isEmpty) return [];
    final list = _lancBox!.values.where((l) {
      if (l.lojaId != _lojaId) return false;
      if (_visaoListaPorCompetencia) {
        if (!LancamentoFinanceiroCompetenciaUi.competenciaNoMes(
          l,
          _mesSelecionado.year,
          _mesSelecionado.month,
        )) {
          return false;
        }
      } else {
        if (!_entraListaPorPagamento(l)) return false;
      }
      if (_filtroStatus != null) {
        if (_filtroStatus == FinanceiroStatusLancamento.pago) {
          if (!FinanceiroStatusLancamento.statusLiquidado(l.status)) return false;
        } else if (l.status != _filtroStatus) {
          return false;
        }
      }
      if (!_passaFiltroTipo(l)) return false;
      return true;
    }).toList();
    if (_visaoListaPorCompetencia) {
      list.sort((a, b) {
        final c = b.dataLancamento.compareTo(a.dataLancamento);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
    } else {
      list.sort(
        (a, b) => b.dataEfetivaPagamentoOuLancamento
            .compareTo(a.dataEfetivaPagamentoOuLancamento),
      );
    }
    return list;
  }

  Widget _cabecalhoKpis() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.insights_outlined, size: 22, color: _primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KPIs oficiais do período (por pagamento)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Indicadores baseados em pagamentos efetivos no mês civil selecionado.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerListaVisao() {
    final comp = _visaoListaPorCompetencia;
    final bg = comp ? Colors.indigo.shade50 : Colors.teal.shade50;
    final border = comp ? Colors.indigo.shade100 : Colors.teal.shade100;
    final icon = comp ? Icons.account_tree_outlined : Icons.payments_outlined;
    final iconColor = comp ? Colors.indigo.shade800 : Colors.teal.shade800;
    final titulo = comp
        ? 'Lista por competência — visão gerencial'
        : 'Lista por pagamento — alinhada aos KPIs';
    final subtitulo =
        comp ? 'Não altera os KPIs do topo' : 'Mesmo recorte dos indicadores oficiais';
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            height: 1.25,
            color: Colors.grey.shade900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitulo,
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(height: 6),
                  textos,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(child: textos),
              ],
            );
          },
        ),
      ),
    );
  }

  InputDecoration _decorationFiltroLista(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }

  Widget _dropdownFiltroStatus() {
    return DropdownButtonFormField<String?>(
      value: _filtroStatus,
      isExpanded: true,
      decoration: _decorationFiltroLista('Status'),
      items: const [
        DropdownMenuItem(value: null, child: Text('Todos')),
        DropdownMenuItem(
          value: FinanceiroStatusLancamento.pago,
          child: Text('Pago'),
        ),
        DropdownMenuItem(
          value: FinanceiroStatusLancamento.pendente,
          child: Text('Pendente'),
        ),
      ],
      onChanged: (v) {
        setState(() => _filtroStatus = v);
        _persistirUiPrefs();
      },
    );
  }

  Widget _dropdownFiltroTipo() {
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      value: _filtroTipoGrupo,
      decoration: _decorationFiltroLista('Tipo / visão'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todos'),
        ),
        const DropdownMenuItem<String?>(
          value: FinanceiroUiPrefsService.filtroGrupoEquipe,
          child: Text('Equipe / pró-labore'),
        ),
        ...FinanceiroTipoLancamento.todos.map(
          (t) => DropdownMenuItem<String?>(
            value: t,
            child: Text(
              FinanceiroTipoLancamento.legivel(t),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (v) {
        setState(() => _filtroTipoGrupo = v);
        _persistirUiPrefs();
      },
    );
  }

  Widget _barraFiltrosDropdowns() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final empilhar = constraints.maxWidth < 480;
        if (empilhar) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dropdownFiltroStatus(),
              const SizedBox(height: 8),
              _dropdownFiltroTipo(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _dropdownFiltroStatus()),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _dropdownFiltroTipo()),
          ],
        );
      },
    );
  }

  Widget _barraFiltros() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Lista de lançamentos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Por pagamento'),
                  selected: !_visaoListaPorCompetencia,
                  onSelected: (_) {
                    setState(() => _visaoListaPorCompetencia = false);
                    _persistirUiPrefs();
                  },
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Por competência'),
                  selected: _visaoListaPorCompetencia,
                  onSelected: (_) {
                    setState(() => _visaoListaPorCompetencia = true);
                    _persistirUiPrefs();
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: _bannerListaVisao(),
            ),
            _barraFiltrosDropdowns(),
          ],
        ),
      ),
    );
  }

  Widget _blocoComposicaoPeriodo() {
    final m = _moduloMes;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Composição do período (lançamentos pagos)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 10),
            _linhaComp('Gastos fixos pagos', m.totalGastosFixos),
            _linhaComp('Gastos variáveis pagos', m.totalGastosVariaveis),
            _linhaComp('Despesas operacionais (legado)', m.totalDespesasOperacionais),
            _linhaComp('Equipe / pró-labore', m.totalPagamentosEquipe),
            const Divider(height: 20),
            _linhaComp('Compras de mercadoria', m.totalCompraMercadoria),
            _linhaComp('Investimentos', m.totalInvestimentos),
            _linhaComp('Retiradas', m.totalRetiradas),
            _linhaComp('Entradas extras', m.totalEntradasExtras),
            _linhaComp('Ajustes financeiros', m.totalAjustes, neutro: true),
          ],
        ),
      ),
    );
  }

  Widget _blocoAcoesMes() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gastos fixos (mês selecionado)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (_lancBox == null || _loading) ? null : _gerarGastosFixosMes,
                    icon: const Icon(Icons.add_chart, size: 18),
                    label: const Text('Gerar do mês'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (_lancBox == null || _loading) ? null : _quitarGastosFixosLote,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Quitar gerados'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocoCompetenciaInfo() {
    final box = _lancBox;
    if (box == null || _lojaId.isEmpty) return const SizedBox.shrink();
    final ini = DateTime(_mesSelecionado.year, _mesSelecionado.month, 1);
    final fim = DateTime(
      _mesSelecionado.year,
      _mesSelecionado.month + 1,
      0,
      23,
      59,
      59,
      999,
    );
    final pend =
        LancamentoFinanceiroCompetenciaUi.contarPendentesCompetenciaMes(
      box.values,
      _lojaId,
      _mesSelecionado.year,
      _mesSelecionado.month,
    );
    final fora = LancamentoFinanceiroCompetenciaUi
        .contarPagosNoMesComCompetenciaOutra(
      box.values,
      _lojaId,
      _mesSelecionado.year,
      _mesSelecionado.month,
      ini,
      fim,
    );
    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.date_range, size: 18, color: Colors.blue.shade800),
                const SizedBox(width: 6),
                Text(
                  'Competência × pagamento',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Pendentes com competência neste mês: $pend',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
            Text(
              'Pagos neste mês (data) com competência em outro período: $fora',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _gerarGastosFixosMes() async {
    if (_lancBox == null || _lojaId.isEmpty) return;
    final gBox = await FinanceiroHiveStore.openGastosFixosBox(_lojaId);
    if (!mounted) return;
    if (gBox == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir gastos fixos.')),
      );
      return;
    }
    final sessao = await Hive.openBox('sessao');
    final u = (sessao.get('usuario_logado') ?? '').toString().trim();
    try {
      final r = await GastoFixoLancamentoService.gerarSugestoesMes(
        gastosBox: gBox,
        lancBox: _lancBox!,
        lojaId: _lojaId,
        ano: _mesSelecionado.year,
        mes: _mesSelecionado.month,
        usuarioId: u,
        usuarioNome: u,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Criados ${r.criados}. Já existiam ${r.puladosJaExistiam}. '
            'Ignorados: ${r.ignoradosInativosOuValorZero}.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _quitarGastosFixosLote() async {
    if (_lancBox == null || _lojaId.isEmpty) return;
    final n = GastoFixoLancamentoService.contarGeradosPendentesCompetencia(
      lancBox: _lancBox!,
      lojaId: _lojaId,
      competenciaAno: _mesSelecionado.year,
      competenciaMes: _mesSelecionado.month,
    );
    if (n == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nenhum lançamento gerado de gasto fixo pendente para esta competência.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    var dataPg = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Quitar gastos fixos gerados'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Serão marcados como pagos $n lançamento(s) gerados pelo cadastro '
                    '(origem gasto fixo, referência gf_gen, competência '
                    '${_mesSelecionado.month}/${_mesSelecionado.year}). '
                    'Lançamentos manuais não são alterados.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Data de pagamento'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(dataPg)),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: dataPg,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) {
                          setLocal(() => dataPg = d);
                        }
                      },
                    ),
                  ),
                ],
              ),
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
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await GastoFixoLancamentoService.quitarGeradosPendentesCompetencia(
        lancBox: _lancBox!,
        lojaId: _lojaId,
        competenciaAno: _mesSelecionado.year,
        competenciaMes: _mesSelecionado.month,
        dataPagamento: dataPg,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Quitados: ${res.afetados} lançamento(s).')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Widget _linhaComp(String r, double v, {bool neutro = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(r, style: const TextStyle(fontSize: 13))),
          Text(
            _moeda.format(v),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: neutro ? Colors.grey.shade800 : Colors.grey.shade900,
            ),
          ),
        ],
      ),
    );
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
          const AppHelpIconButton(iconColor: Colors.white),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: (_loading ||
                    _lojaId.isEmpty ||
                    _acessoNegado ||
                    _erro != null)
                ? null
                : _abrirEscolhaPdf,
            tooltip: 'Exportar PDF',
          ),
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
                      if (_lancBox == null && _lojaId.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Colors.amber.shade800, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Não foi possível abrir o armazenamento local de lançamentos. '
                                      'Os registros podem existir no aparelho; toque em Atualizar ou reinicie o app.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: _loading ? null : () => _mudarMes(-1),
                                icon: const Icon(Icons.chevron_left),
                                tooltip: 'Mês anterior',
                              ),
                              Expanded(
                                child: Text(
                                  DateFormat.yMMMM('pt_BR')
                                      .format(_mesSelecionado),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _muted,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _loading ? null : () => _mudarMes(1),
                                icon: const Icon(Icons.chevron_right),
                                tooltip: 'Próximo mês',
                              ),
                            ],
                          ),
                          if (!_mesmoMesCivil(
                            _mesSelecionado,
                            DateTime(
                              DateTime.now().year,
                              DateTime.now().month,
                            ),
                          ))
                            TextButton(
                              onPressed: _loading ? null : _irParaMesAtual,
                              child: const Text('Mês atual'),
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          ActionChip(
                            label: const Text('Este mês'),
                            onPressed: _loading ? null : _irParaMesAtual,
                          ),
                          ActionChip(
                            label: const Text('Mês anterior'),
                            onPressed: _loading ? null : () => _mudarMes(-1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _cabecalhoKpis(),
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
                      const SizedBox(height: 12),
                      _blocoComposicaoPeriodo(),
                      const SizedBox(height: 6),
                      Text(
                        'Competência organiza o lançamento; pagamento impacta os indicadores.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      _barraFiltros(),
                      const SizedBox(height: 10),
                      _blocoAcoesMes(),
                      const SizedBox(height: 10),
                      _blocoCompetenciaInfo(),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _chipAcao(
                            icon: Icons.dashboard_customize_outlined,
                            label: 'Resumo consolidado',
                            onTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      FinanceiroResumoConsolidadoScreen(
                                    lojaId: _lojaId,
                                    mesInicial: _mesSelecionado,
                                  ),
                                ),
                              );
                            },
                          ),
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
                            icon: Icons.payments_outlined,
                            label: 'Contas a pagar',
                            onTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ContasPagarScreen(),
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
                          _chipAcao(
                            icon: Icons.storefront_outlined,
                            label: 'Conferência de compras',
                            onTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ControleComprasFornecedorScreen(
                                    lojaId: _lojaId,
                                  ),
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
                          Text(
                            'Lançamentos (${_lancamentosFiltrados.length})',
                            style: const TextStyle(
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
                            child: const Text('Lista completa'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_lancamentosFiltrados.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _lancBox == null
                                  ? 'Armazenamento de lançamentos indisponível.'
                                  : 'Nenhum lançamento no período/filtros. Ajuste o mês ou os filtros.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        )
                      else
                        ..._lancamentosFiltrados
                            .take(60)
                            .map(_tileLancamento),
                      if (_lancamentosFiltrados.length > 60)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Mostrando 60 de ${_lancamentosFiltrados.length}. Refine filtros ou abra a lista completa.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  FinanceiroPdfPayload _montarPayloadPdf() {
    final y = _mesSelecionado.year;
    final m = _mesSelecionado.month;
    final ini = DateTime(y, m, 1);
    final fim = DateTime(y, m + 1, 0, 23, 59, 59, 999);
    final rv = _resumoVendasMes;
    final det = _lancBox == null
        ? <LancamentoFinanceiro>[]
        : (FinanceiroService.lancamentosPagosNoPeriodo(
            _lancBox!,
            _lojaId,
            ini,
            fim,
          ).toList()
          ..sort(
            (a, b) => b.dataEfetivaPagamentoOuLancamento.compareTo(
              a.dataEfetivaPagamentoOuLancamento,
            ),
          ));

    return FinanceiroPdfPayload(
      nomeLoja: _nomeLojaExibicao,
      lojaId: _lojaId,
      periodoInicio: ini,
      periodoFim: fim,
      modulo: _moduloMes,
      totalVendido: rv?.venda ?? 0,
      custoProdutos: rv?.custo ?? 0,
      taxas: rv?.taxas ?? 0,
      lucroOperacionalVendas: rv?.lucro ?? 0,
      totalDinheiro: rv?.dinheiro ?? 0,
      totalPix: rv?.pix ?? 0,
      totalCartao: rv?.cartao ?? 0,
      totalContasReceberAberto: _totalContasReceberPendentes,
      lancamentosDetalhe: det,
      vendasDetalhe: const [],
    );
  }

  Future<void> _exportarPdf(FinanceiroPdfTipo tipo) async {
    try {
      await FinanceiroPdfService.gerar(
        tipo: tipo,
        payload: _montarPayloadPdf(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar PDF: $e')),
      );
    }
  }

  Future<void> _abrirEscolhaPdf() async {
    final tipo = await showModalBottomSheet<FinanceiroPdfTipo>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Exportar relatório em PDF',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...FinanceiroPdfTipo.values.map(
              (t) => ListTile(
                title: Text(FinanceiroPdfService.nomeTipo(t)),
                onTap: () => Navigator.pop(ctx, t),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (tipo != null && mounted) {
      await _exportarPdf(tipo);
    }
  }

  Widget _cardResumo() {
    final rv = _resumoVendasMes;
    final lucroOpVendas = rv?.lucro;
    final resultadoGerencial = lucroOpVendas != null
        ? FinanceiroService.resultadoGerencialComModulo(
            lucroOperacionalVendas: lucroOpVendas,
            modulo: _moduloMes,
          )
        : null;
    final somaFormas = rv != null
        ? rv.dinheiro + rv.pix + rv.cartao
        : 0.0;
    final fluxoCaixa = rv != null
        ? FinanceiroService.fluxoCaixaComVendas(
            somaFormasPagamentoVendas: somaFormas,
            modulo: _moduloMes,
          )
        : _moduloMes.impactoLiquidoModulo;
    final entrouSimples = somaFormas + _moduloMes.totalEntradasExtras;
    final despesasResumo = _moduloMes.despesasParaResultadoGerencial;

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
            Text(
              'Visão simples',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Quanto entrou',
                    _moeda.format(entrouSimples),
                    _success,
                  ),
                ),
                Expanded(
                  child: _miniMetric(
                    'Quanto saiu',
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
                    'Quanto sobrou (fluxo de caixa)',
                    _moeda.format(fluxoCaixa),
                    fluxoCaixa >= 0 ? _primary : Colors.redAccent,
                  ),
                ),
                Expanded(
                  child: _miniMetric(
                    'Lucro das vendas',
                    _moeda.format(rv?.lucro ?? 0),
                    (rv?.lucro ?? 0) >= 0 ? _success : Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Gastos com mercadoria',
                    _moeda.format(_moduloMes.totalCompraMercadoria),
                    Colors.brown,
                  ),
                ),
                Expanded(
                  child: _miniMetric(
                    'Despesas',
                    _moeda.format(despesasResumo),
                    Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Contas a receber (aberto)',
                    _moeda.format(_totalContasReceberPendentes),
                    const Color(0xFF6366F1),
                  ),
                ),
                Expanded(
                  child: _miniMetric(
                    _visaoListaPorCompetencia
                        ? 'A pagar (competência)'
                        : 'Contas a pagar (aberto)',
                    _moeda.format(_resumoContasPagar.totalAberto),
                    Colors.brown.shade700,
                  ),
                ),
              ],
            ),
            if (!_visaoListaPorCompetencia) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _miniMetric(
                      'CP vencidas',
                      _moeda.format(_resumoContasPagar.totalVencido),
                      Colors.redAccent,
                    ),
                  ),
                  Expanded(
                    child: _miniMetric(
                      'CP pagas no mês',
                      _moeda.format(_resumoContasPagar.totalPagoNoMes),
                      _success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _miniMetric(
                      'Fluxo projetado (CP)',
                      _moeda.format(_resumoContasPagar.fluxoProjetado),
                      Colors.teal.shade700,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _miniMetric(
                    'Taxas pagas',
                    _moeda.format(rv?.taxas ?? 0),
                    Colors.purple,
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Detalhes técnicos',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                subtitle: Text(
                  'CMV, DRE, resultado gerencial, fluxo de caixa e lançamentos',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
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
                            'Lucro operacional de vendas',
                            _moeda.format(rv.lucro),
                            _success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _miniMetric(
                            'Resultado gerencial do mês',
                            _moeda.format(resultadoGerencial ?? 0),
                            resultadoGerencial != null &&
                                    resultadoGerencial >= 0
                                ? _success
                                : Colors.redAccent,
                          ),
                        ),
                        Expanded(
                          child: _miniMetric(
                            'Fluxo de caixa (vendas + lançamentos)',
                            _moeda.format(fluxoCaixa),
                            fluxoCaixa >= 0 ? _primary : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _miniMetric(
                            'Fluxo de caixa (só lançamentos)',
                            _moeda.format(_moduloMes.impactoLiquidoModulo),
                            _moduloMes.impactoLiquidoModulo >= 0
                                ? _primary
                                : Colors.redAccent,
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
                          'Entradas extras (caixa)',
                          _moeda.format(_moduloMes.totalEntradasExtras),
                          _success,
                        ),
                      ),
                      Expanded(
                        child: _miniMetric(
                          'Saídas (módulo, todas)',
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
                          'Compra mercadoria (caixa)',
                          _moeda.format(_moduloMes.totalCompraMercadoria),
                          Colors.brown,
                        ),
                      ),
                      Expanded(
                        child: _miniMetric(
                          'Investimentos / retiradas',
                          _moeda.format(
                            _moduloMes.totalInvestimentos +
                                _moduloMes.totalRetiradas,
                          ),
                          Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lucro operacional de vendas = vendas − custoProdutos − taxas (config/fechamento). '
                    'Resultado gerencial = esse lucro − (gastos fixos + variáveis + despesa legada + equipe) + ajustes; '
                    'não inclui compra de mercadoria (CMV nas vendas), investimento, retirada nem entrada extra. '
                    'Fluxo de caixa = recebimentos (dinheiro+pix+cartão) + entradas extras − saídas + ajustes. '
                    'Compra paga é saída de caixa; CMV é o custo dos produtos vendidos. O sistema não desconta '
                    'a compra inteira do lucro das vendas para evitar duplicidade. '
                    'Gastos fixos: use “Gerar lançamentos do mês” na tela de cadastro ou lance manualmente. '
                    'Sugestões ficam pendentes até marcar como pagas.',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
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
        color: color.withOpacity(0.08),
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

  void _snack(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? _error : _success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  FinanceiroLancamentoAcaoInfo _acao(LancamentoFinanceiro l) =>
      FinanceiroLancamentoExclusaoService.acaoParaUi(
        l,
        contas: _contasReceberCache,
        lojaId: _lojaId,
        lancamentosLoja: _lancBox?.values ?? const [],
      );

  Future<void> _editarLancamento(LancamentoFinanceiro l) async {
    final acao = _acao(l);
    debugPrint('[FIN-GESTAO][EDITAR-CLICK] id=${l.id} key=${l.key}');
    if (_ehCrSemVinculoSeguro(acao)) {
      await _confirmarExcluirSomenteFinanceiro(l);
      return;
    }
    if (!acao.podeEditar) {
      _snack(
        acao.motivoBloqueio ?? FinanceiroLancamentoAcaoResolver.msgVinculoProcesso,
        erro: true,
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FinanceiroLancamentosScreen(
          lojaId: _lojaId,
          lancamentoInicial: l,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _confirmarExcluirLancamento(LancamentoFinanceiro l) async {
    debugPrint('[FIN-GESTAO][EXCLUIR-CLICK] id=${l.id} key=${l.key}');
    final acao = _acao(l);
    if (acao.ehBaixaCr) {
      _snack('Este lançamento veio de Contas a Receber. Use Estornar baixa.', erro: true);
      return;
    }
    if (!acao.podeExcluir) {
      _snack(
        acao.motivoBloqueio ?? FinanceiroLancamentoAcaoResolver.msgVinculoProcesso,
        erro: true,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(
          'Deseja excluir "${l.descricao.isEmpty ? '(sem descrição)' : l.descricao}"?\n'
          'Status: ${FinanceiroStatusLancamento.legivel(l.status)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: _lojaId,
      lancamento: l,
    );
    debugPrint('[FIN-GESTAO][RESULTADO] excluir sucesso=${r.sucesso}');
    await _load();
    if (!mounted) return;
    _snack(
      r.sucesso
          ? 'Lançamento excluído.'
          : (r.mensagemErro ?? 'Não foi possível excluir.'),
      erro: !r.sucesso,
    );
  }

  bool _ehCrSemVinculoSeguro(FinanceiroLancamentoAcaoInfo acao) =>
      acao.ehBaixaCr &&
      (acao.podeExcluirSomenteFinanceiro || acao.bloqueadoEstorno);

  Future<void> _onAcaoLancamentoClick(LancamentoFinanceiro l) async {
    debugPrint('[FIN-GESTAO][ACAO-CLICK] id=${l.id} key=${l.key}');
    final acao = _acao(l);
    debugPrint(
      '[FIN-GESTAO][RESOLVEU-ACAO] id=${l.id} editar=${acao.podeEditar} '
      'excluir=${acao.podeExcluir} estornar=${acao.podeEstornar} '
      'financeiroOnly=${acao.podeExcluirSomenteFinanceiro} '
      'bloqueadoEstorno=${acao.bloqueadoEstorno} baixaCr=${acao.ehBaixaCr}',
    );
    if (_ehCrSemVinculoSeguro(acao)) {
      debugPrint('[FIN-GESTAO][CR-SEM-VINCULO] id=${l.id}');
      await _confirmarExcluirSomenteFinanceiro(l);
      return;
    }
    if (acao.mostrarExcluirDuplicado) {
      debugPrint('[FIN-GESTAO][CR-DUPLICADO] id=${l.id}');
      await _confirmarExcluirDuplicado(l);
      return;
    }
    if (acao.podeEstornar) {
      await _confirmarEstornarBaixa(l);
      return;
    }
    if (acao.podeExcluir) {
      await _confirmarExcluirLancamento(l);
      return;
    }
    if (acao.podeEditar) {
      await _editarLancamento(l);
      return;
    }
    _snack(
      acao.motivoBloqueio ?? FinanceiroLancamentoAcaoResolver.msgVinculoProcesso,
      erro: true,
    );
  }

  Future<void> _confirmarExcluirSomenteFinanceiro(LancamentoFinanceiro l) async {
    debugPrint(
      '[FIN-GESTAO][EXCLUIR-CLICK] financeiro-only id=${l.id} key=${l.key}',
    );
    final acao = _acao(l);
    if (!_ehCrSemVinculoSeguro(acao)) {
      _snack(
        acao.motivoBloqueio ??
            FinanceiroLancamentoExclusaoService.msgEstornoSemVinculoComOpcaoExclusao,
        erro: true,
      );
      return;
    }
    debugPrint('[FIN-GESTAO][EXCLUIR-SOMENTE-FINANCEIRO-MODAL] id=${l.id}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estorno não disponível'),
        content: Text(
          FinanceiroLancamentoExclusaoService.msgModalExcluirSomenteFinanceiroCr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir lançamento'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    debugPrint('[FIN-GESTAO][EXCLUIR-SOMENTE-FINANCEIRO-CONFIRMOU] id=${l.id}');
    final r =
        await FinanceiroLancamentoExclusaoService.excluirSomenteLancamentoFinanceiroLegado(
      lojaId: _lojaId,
      lancamento: l,
    );
    debugPrint('[FIN-GESTAO][RESULTADO] financeiro-only sucesso=${r.sucesso}');
    await _load();
    if (!mounted) return;
    debugPrint('[FIN-GESTAO][REFRESH-LISTA] itens=${_lancamentosFiltrados.length}');
    _snack(
      r.sucesso
          ? FinanceiroLancamentoExclusaoService.msgSucessoExcluirSomenteFinanceiro
          : (r.mensagemErro ?? 'Não foi possível excluir.'),
      erro: !r.sucesso,
    );
  }

  Future<void> _confirmarExcluirDuplicado(LancamentoFinanceiro l) async {
    debugPrint('[FIN-GESTAO][EXCLUIR-DUP-CLICK] id=${l.id} key=${l.key}');
    final acao = _acao(l);
    if (!acao.mostrarExcluirDuplicado) {
      _snack(
        acao.motivoBloqueio ??
            'Não foi possível confirmar duplicidade com segurança.',
        erro: true,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento duplicado?'),
        content: Text(
          FinanceiroLancamentoExclusaoService.msgModalExcluirDuplicadoBaixaCr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir duplicado'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r =
        await FinanceiroLancamentoExclusaoService
            .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: _lojaId,
      lancamento: l,
      lancamentosLoja: _lancBox?.values,
    );
    await _load();
    if (!mounted) return;
    debugPrint('[FIN-GESTAO][REFRESH-LISTA] itens=${_lancamentosFiltrados.length}');
    _snack(
      r.sucesso
          ? FinanceiroLancamentoExclusaoService.msgSucessoExcluirDuplicado
          : (r.mensagemErro ?? 'Não foi possível excluir.'),
      erro: !r.sucesso,
    );
  }

  Future<void> _confirmarEstornarBaixa(LancamentoFinanceiro l) async {
    debugPrint('[FIN-GESTAO][ESTORNAR-CLICK] id=${l.id} key=${l.key}');
    final acao = _acao(l);
    if (acao.bloqueadoEstorno || (acao.ehBaixaCr && !acao.podeEstornar)) {
      await _confirmarExcluirSomenteFinanceiro(l);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estornar baixa?'),
        content: Text(
          'Deseja estornar esta baixa?\n'
          '${l.descricao.isEmpty ? '(sem descrição)' : l.descricao}\n'
          'A parcela vinculada será reaberta.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estornar baixa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: _lojaId,
      lancamento: l,
    );
    debugPrint('[FIN-GESTAO][RESULTADO] estorno sucesso=${r.sucesso}');
    if (!r.sucesso && (r.bloqueado || acao.ehBaixaCr)) {
      await _confirmarExcluirSomenteFinanceiro(l);
      return;
    }
    await _load();
    if (!mounted) return;
    debugPrint('[FIN-GESTAO][REFRESH-LISTA] itens=${_lancamentosFiltrados.length}');
    _snack(
      r.sucesso
          ? 'Baixa estornada. A parcela foi reaberta.'
          : (r.mensagemErro ?? 'Não foi possível estornar.'),
      erro: !r.sucesso,
    );
  }

  Widget _tileLancamento(LancamentoFinanceiro l) {
    final acao = _acao(l);
    final chipOrigem = chipOrigemAutomaticaLancamento(l);
    final crSemVinculo = _ehCrSemVinculoSeguro(acao);
    final IconData acaoIcon;
    final Color acaoColor;
    final String acaoTooltip;
    if (acao.mostrarExcluirDuplicado) {
      acaoIcon = Icons.delete_outline;
      acaoColor = _error;
      acaoTooltip = 'Excluir lançamento duplicado';
    } else if (crSemVinculo) {
      acaoIcon = Icons.delete_outline;
      acaoColor = _error;
      acaoTooltip = 'Excluir somente lançamento';
    } else if (acao.mostrarEstornar) {
      acaoIcon = Icons.undo;
      acaoColor = _warning;
      acaoTooltip = 'Estornar baixa';
    } else if (acao.mostrarExcluir) {
      acaoIcon = Icons.delete_outline;
      acaoColor = _error;
      acaoTooltip = 'Excluir';
    } else {
      acaoIcon = Icons.more_horiz;
      acaoColor = Colors.grey.shade600;
      acaoTooltip = 'Ações';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _primary.withOpacity(0.12),
                  child: const Icon(Icons.receipt_long,
                      color: Color(0xFF6366F1), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.descricao.isEmpty ? '(sem descrição)' : l.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (chipOrigem != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            chipOrigem,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        '${FinanceiroTipoLancamento.legivel(l.tipo)} · '
                        '${FinanceiroStatusLancamento.legivel(l.status)} · '
                        '${LancamentoFinanceiroCompetenciaUi.subtituloCompetenciaPagamento(l, _fmtMesAnoPt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          height: 1.25,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _moeda.format(l.valor),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (acao.mostrarEditar)
                  IconButton(
                    tooltip: 'Editar',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const Icon(Icons.edit_outlined, size: 20, color: _primary),
                    onPressed: () => _editarLancamento(l),
                  ),
                IconButton(
                  tooltip: acaoTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(acaoIcon, size: 20, color: acaoColor),
                  onPressed: () => _onAcaoLancamentoClick(l),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
