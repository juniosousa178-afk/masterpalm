// lib/screens/contas_receber_screen.dart
// Contas a receber (vendas fiadas e títulos). Melhoria financeira.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/hive_box_names.dart';
import '../models/cliente.dart';
import '../models/conta_receber.dart';
import '../services/conta_receber_recebimento_caixa_service.dart';
import '../services/loja_id_service.dart';
import '../services/notificacao_service.dart';
import '../services/pagamentos_service.dart';
import '../utils/moeda_input_formatter.dart';
import '../widgets/app_help_icon_button.dart';
import '../widgets/moeda_text_field.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _warningColor = Color(0xFFF59E0B);
const Color _cardColor = Color(0xFFFFFFFF);
const Color _backgroundColor = Color(0xFFF8FAFC);

class ContasReceberScreen extends StatefulWidget {
  const ContasReceberScreen({super.key});

  @override
  State<ContasReceberScreen> createState() => _ContasReceberScreenState();
}

class _ContasReceberScreenState extends State<ContasReceberScreen> {
  bool _loading = true;
  bool _erroResolucaoLoja = false;
  String? _lojaId;
  late Box<ContaReceber> _box;
  String _filtro = 'pendentes'; // pendentes | pagas | vencidas | todas
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  String _nomeLojaMensagem = 'nossa loja';
  String _pixKeyMensagem = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (_lojaId == null || _lojaId!.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erroResolucaoLoja = true;
        });
      }
      return;
    }
    try {
      final name = HiveBoxNames.contasReceber(_lojaId!);
      _box = Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
      await _carregarTemplateMensagem();
      await _verificarLembretesDoisDias();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erroResolucaoLoja = true;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  List<ContaReceber> get _lista {
    final hoje = DateTime.now();
    var list = _box.values.where((c) => c.lojaId == _lojaId).toList();
    list.sort((a, b) => b.dataVencimento.compareTo(a.dataVencimento));
    if (_filtro == 'pendentes') list = list.where((c) => !c.pago).toList();
    if (_filtro == 'vencidas') list = list.where((c) => !c.pago && c.dataVencimento.isBefore(hoje)).toList();
    if (_filtro == 'pagas') list = list.where((c) => c.pago).toList();
    return list;
  }

  Future<void> _marcarPago(ContaReceber c) async {
    await _abrirDialogRecebimento(c);
  }

  void _mostrarExplicacaoFiadoECaixa() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 26),
            SizedBox(width: 10),
            Expanded(child: Text('Fiado e caixa')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quando a venda é fiada',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Na confirmação da venda: o estoque baixa, a venda e o cliente são registrados e aparecem aqui as parcelas a receber. '
                'O valor fiado não é lançado em Dinheiro, Pix nem Cartão na própria venda — ou seja, não entra no caixa naquele momento.',
              ),
              const SizedBox(height: 16),
              Text(
                'Relatórios (total vendido)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'O total da venda continua contando no faturamento do período, porque a venda ocorreu de fato. '
                'Isso é separado do “dinheiro que entrou no caixa”.',
              ),
              const SizedBox(height: 16),
              Text(
                'Quando você recebe (ícone de confirmar)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ao registrar o recebimento, o valor entra no módulo financeiro como entrada extra, na data em que você confirmou. '
                'Assim o fluxo de caixa reflete o dinheiro (ou Pix/cartão) que realmente entrou.',
              ),
              const SizedBox(height: 16),
              Text(
                'Duplica pagamento?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Não: na venda fiada as formas de pagamento ficam zeradas para o fiado; o caixa só soma de novo quando você recebe aqui. '
                'São duas coisas: quanto vendeu vs quanto entrou no caixa.',
              ),
              const SizedBox(height: 16),
              Text(
                'Pagamento parcial e parcelas',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Você pode receber só uma parte do saldo (o restante fica na mesma conta) ou marcar para dividir o saldo restante em novas parcelas com vencimentos que você define.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDialogRecebimento(ContaReceber c) async {
    if (_lojaId == null || _lojaId!.isEmpty) return;
    final saldo = c.valor;
    if (saldo <= 0) return;

    final valorCtrl = TextEditingController(text: MoedaInputFormatter.format(saldo));
    String forma = 'Dinheiro';
    var dataRecebimento = DateTime.now();
    var dividirRestante = false;
    final qtdParcelasCtrl = TextEditingController(text: '2');
    final intervaloCtrl = TextEditingController(text: '30');
    final diasPrimeiroVencCtrl = TextEditingController(text: '30');

    bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                title: const Text('Registrar recebimento'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${c.clienteNome} · Saldo ${_currency.format(saldo)}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      MoedaTextField(
                        controller: valorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Valor recebido agora',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(forma),
                        value: forma,
                        decoration: const InputDecoration(
                          labelText: 'Forma (caixa)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                          DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                          DropdownMenuItem(value: 'Cartão', child: Text('Cartão')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => forma = v);
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Data do recebimento no caixa'),
                        subtitle: Text(DateFormat('dd/MM/yyyy').format(dataRecebimento)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: dataRecebimento,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setLocal(() => dataRecebimento = d);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Dividir o saldo restante em parcelas'),
                        value: dividirRestante,
                        onChanged: (v) => setLocal(() => dividirRestante = v),
                      ),
                      if (dividirRestante) ...[
                        TextField(
                          controller: qtdParcelasCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Nº de parcelas do saldo',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: intervaloCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Intervalo entre parcelas (dias)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: diasPrimeiroVencCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '1º vencimento do saldo (dias a partir de hoje)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirmar'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (ok != true || !mounted) return;

      final pago = MoedaInputFormatter.parse(valorCtrl.text).clamp(0.0, saldo);
      if (pago <= 1e-9) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Informe um valor recebido maior que zero.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final hiveKey = c.key is int ? c.key as int : -1;
      await ContaReceberRecebimentoCaixaService.registrarRecebimento(
        lojaId: _lojaId!,
        valor: pago,
        formaPagamento: forma,
        clienteNome: c.clienteNome,
        observacaoConta: c.observacao,
        contaHiveKey: hiveKey,
        parcelaNumero: c.parcelaNumero,
        dataRecebimento: dataRecebimento,
      );

      final restante = (saldo - pago).clamp(0.0, double.infinity);
      final quitado = restante < 0.01;

      if (quitado) {
        c.pago = true;
        await c.save();
      } else if (!dividirRestante) {
        c.valor = restante;
        await c.save();
      } else {
        final n = (int.tryParse(qtdParcelasCtrl.text.trim()) ?? 2).clamp(2, 48);
        final intervalo = (int.tryParse(intervaloCtrl.text.trim()) ?? 30).clamp(1, 120);
        final dias1 = (int.tryParse(diasPrimeiroVencCtrl.text.trim()) ?? 30).clamp(1, 365);
        final partes = ContaReceberRecebimentoCaixaService.parcelarValores(restante, n);
        final baseObs = c.observacao.trim();
        final loja = c.lojaId;
        final cliente = c.clienteNome;
        final dataVenda = c.dataVenda;
        final vendaKey = c.vendaKey;

        await c.delete();

        final baseParcelamento = dataRecebimento;
        for (var i = 0; i < n; i++) {
          final venc = baseParcelamento.add(Duration(days: dias1 + i * intervalo));
          final obsParcela = n > 1
              ? 'Parcela ${i + 1}/$n (saldo)${baseObs.isNotEmpty ? ' · $baseObs' : ''}'
              : (baseObs.isNotEmpty ? baseObs : 'Saldo');
          await _box.add(
            ContaReceber(
              lojaId: loja,
              clienteNome: cliente,
              valor: partes[i],
              dataVencimento: venc,
              dataVenda: dataVenda,
              vendaKey: vendaKey,
              observacao: obsParcela,
              parcelaNumero: i + 1,
              parcelaTotal: n,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {});
      final agora = DateTime.now();
      final retro = dataRecebimento.isBefore(DateTime(agora.year, agora.month, 1));
      final msgBase = quitado
          ? 'Recebimento registrado. Conta quitada.'
          : dividirRestante
              ? 'Recebimento registrado. Saldo dividido em novas parcelas.'
              : 'Recebimento registrado. Saldo atualizado.';
      final msgFinal = retro
          ? '$msgBase\n\n'
              'Este lançamento será registrado em um mês anterior e aparecerá nos relatórios daquele período.'
          : msgBase;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msgFinal),
          backgroundColor: _successColor,
          duration: Duration(seconds: retro ? 8 : 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao registrar: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      valorCtrl.dispose();
      qtdParcelasCtrl.dispose();
      intervaloCtrl.dispose();
      diasPrimeiroVencCtrl.dispose();
    }
  }

  Future<void> _carregarTemplateMensagem() async {
    final cfg = Hive.isBoxOpen('config')
        ? Hive.box('config')
        : await Hive.openBox('config');
    final nome = (cfg.get('store_name') ?? '').toString().trim();
    if (nome.isNotEmpty) _nomeLojaMensagem = nome;
    try {
      final snap = await PagamentosService.paymentsDoc(_lojaId!).get();
      final data = snap.data() ?? const <String, dynamic>{};
      final checkout = (data['checkout'] as Map<String, dynamic>?) ?? {};
      final pix = (checkout['pixKey'] ?? checkout['chavePix'] ?? '').toString().trim();
      if (pix.isNotEmpty) _pixKeyMensagem = pix;
    } catch (_) {
      // Mensagem funciona mesmo sem buscar chave PIX remota.
    }
  }

  Future<void> _verificarLembretesDoisDias() async {
    if (_lojaId == null || _lojaId!.isEmpty) return;
    final hoje = DateTime.now();
    for (final c in _box.values.where((e) => e.lojaId == _lojaId && !e.pago)) {
      final venc = DateTime(c.dataVencimento.year, c.dataVencimento.month, c.dataVencimento.day);
      final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
      final diffDias = venc.difference(baseHoje).inDays;
      if (diffDias == 2 && !c.lembrete2DiasEnviado) {
        await NotificacaoService.enviarNotificacao(
          titulo: 'Conta vence em 2 dias',
          corpo:
              'Cliente ${c.clienteNome} - ${_currency.format(c.valor)} vence em ${DateFormat('dd/MM').format(c.dataVencimento)}.',
        );
        c.lembrete2DiasEnviado = true;
        await c.save();
      }
    }
  }

  Future<void> _cobrarNoWhatsApp(ContaReceber c) async {
    if (_lojaId == null || _lojaId!.isEmpty) return;
    final clientesBoxName = HiveBoxNames.clientes(_lojaId!);
    final clientesBox = Hive.isBoxOpen(clientesBoxName)
        ? Hive.box<Cliente>(clientesBoxName)
        : await Hive.openBox<Cliente>(clientesBoxName);
    final nomeBusca = c.clienteNome.trim().toLowerCase();
    Cliente? cliente;
    for (final item in clientesBox.values) {
      if (item.lojaId == _lojaId && item.nome.trim().toLowerCase() == nomeBusca) {
        cliente = item;
        break;
      }
    }
    final telefone = (cliente?.telefone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    if (telefone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cliente sem telefone cadastrado para cobrança no WhatsApp.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final hoje = DateTime.now();
    final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final venc = DateTime(c.dataVencimento.year, c.dataVencimento.month, c.dataVencimento.day);
    final dias = venc.difference(baseHoje).inDays;
    final faixaPrazo = dias == 2
        ? 'Faltam 2 dias para o vencimento.'
        : dias > 0
            ? 'O vencimento ocorre em $dias dia(s).'
            : dias == 0
                ? 'O vencimento é hoje.'
                : 'Este título está vencido há ${dias.abs()} dia(s).';
    final parcelaTexto = c.parcelaTotal > 1 ? ' (Parcela ${c.parcelaNumero}/${c.parcelaTotal})' : '';
    final linhaPix = _pixKeyMensagem.isNotEmpty ? '\n\nSe preferir, você pode pagar por PIX: $_pixKeyMensagem.' : '';
    final mensagem = Uri.encodeComponent(
      'Olá, ${c.clienteNome}! Tudo bem?\n\n'
      'Aqui é da $_nomeLojaMensagem.\n'
      'Passando para lembrar da sua cobrança$parcelaTexto no valor de ${_currency.format(c.valor)}, '
      'com vencimento em ${DateFormat('dd/MM/yyyy').format(c.dataVencimento)}.\n'
      '$faixaPrazo$linhaPix\n\n'
      'Se precisar, estamos à disposição. Obrigado!',
    );
    final uri = Uri.parse('https://wa.me/$telefone?text=$mensagem');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
      );
    }
  }

  Future<void> _adicionarManual() async {
    final nomeCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    DateTime dataVendaSelecionada = DateTime.now();
    DateTime dataVencimentoSelecionada = DateTime.now().add(const Duration(days: 30));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nova conta a receber'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cliente',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valorCtrl,
                  // iPhone/Safari: teclado "number" puro costuma não ter vírgula/ponto.
                  // Só dígitos + MoedaInputFormatter → vírgula e centavos automáticos (ex.: 1050 → 10,50).
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                    signed: false,
                  ),
                  inputFormatters: [MoedaInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Valor (R\$)',
                    hintText: 'Digite só números: 1500 = R\$ 15,00',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data da venda / lançamento'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(dataVendaSelecionada)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final selecionada = await showDatePicker(
                      context: ctx,
                      initialDate: dataVendaSelecionada,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selecionada == null) return;
                    setDialogState(() {
                      dataVendaSelecionada = selecionada;
                    });
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data de vencimento'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(dataVencimentoSelecionada)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final selecionada = await showDatePicker(
                      context: ctx,
                      initialDate: dataVencimentoSelecionada,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selecionada == null) return;
                    setDialogState(() {
                      dataVencimentoSelecionada = selecionada;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (nomeCtrl.text.trim().isEmpty || valorCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final valor = MoedaInputFormatter.parse(valorCtrl.text);
    if (valor <= 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final dataVenda = DateTime(
      dataVendaSelecionada.year,
      dataVendaSelecionada.month,
      dataVendaSelecionada.day,
    );
    final dataVencimento = DateTime(
      dataVencimentoSelecionada.year,
      dataVencimentoSelecionada.month,
      dataVencimentoSelecionada.day,
    );
    final conta = ContaReceber(
      lojaId: _lojaId!,
      clienteNome: nomeCtrl.text.trim(),
      valor: valor,
      dataVencimento: dataVencimento,
      dataVenda: dataVenda,
      observacao: obsCtrl.text.trim(),
    );
    await _box.add(conta);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta a receber adicionada.'), backgroundColor: _successColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contas a receber')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.store_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Não foi possível carregar a loja.', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Verifique sua conexão e tente novamente.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() { _erroResolucaoLoja = false; _loading = true; });
                    _init();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }
    final list = _lista;
    final totalPendente = list.where((c) => !c.pago).fold<double>(0, (s, c) => s + c.valor);
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('Contas a receber'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'Como funciona o fiado e o caixa',
            onPressed: _mostrarExplicacaoFiadoECaixa,
          ),
          const AppHelpIconButton(iconColor: Colors.white),
          PopupMenuButton<String>(
            initialValue: _filtro,
            onSelected: (v) => setState(() => _filtro = v),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'pendentes', child: Text('Pendentes')),
              const PopupMenuItem(value: 'vencidas', child: Text('Vencidas')),
              const PopupMenuItem(value: 'pagas', child: Text('Pagas')),
              const PopupMenuItem(value: 'todas', child: Text('Todas')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _init,
        color: _primaryColor,
        child: Column(
          children: [
          if ((_filtro == 'pendentes' || _filtro == 'vencidas') && list.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _warningColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warningColor.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total a receber:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(_currency.format(totalPendente), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text('Nenhuma conta ${_filtro == "pendentes" ? "pendente" : _filtro == "vencidas" ? "vencida" : _filtro == "pagas" ? "paga" : ""}.', style: TextStyle(color: Colors.grey.shade600)),
                        if (_filtro != 'todas')
                          TextButton.icon(
                            onPressed: _adicionarManual,
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar conta'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      final vencida = !c.pago && c.dataVencimento.isBefore(DateTime.now());
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: _cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: vencida ? const BorderSide(color: _warningColor, width: 1) : BorderSide.none,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: c.pago ? _successColor.withOpacity(0.2) : _primaryColor.withOpacity(0.2),
                            child: Icon(c.pago ? Icons.check : Icons.schedule, color: c.pago ? _successColor : _primaryColor),
                          ),
                          title: Text(c.clienteNome, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Venc: ${DateFormat('dd/MM/yyyy').format(c.dataVencimento)}${c.observacao.isNotEmpty ? " · ${c.observacao}" : ""}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_currency.format(c.valor), style: TextStyle(fontWeight: FontWeight.bold, color: c.pago ? Colors.grey : _primaryColor)),
                              if (!c.pago) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.chat_outlined),
                                  onPressed: () => _cobrarNoWhatsApp(c),
                                  tooltip: 'Cobrar no WhatsApp',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline),
                                  onPressed: () => _marcarPago(c),
                                  tooltip: 'Registrar recebimento',
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionarManual,
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
        backgroundColor: _primaryColor,
      ),
    );
  }
}

