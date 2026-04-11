// lib/screens/contas_receber_screen.dart
// Contas a receber (vendas fiadas e títulos). Melhoria financeira.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../models/conta_receber.dart';
import '../services/loja_id_service.dart';
import '../widgets/app_help_icon_button.dart';

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
    c.pago = true;
    await c.save();
    setState(() {});
  }

  Future<void> _adicionarManual() async {
    final nomeCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final diasCtrl = TextEditingController(text: '30');
    final obsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Valor (R\$)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: diasCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Vencimento em (dias)',
                  border: OutlineInputBorder(),
                ),
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
    );
    if (ok != true || !mounted) return;
    final valor = double.tryParse(valorCtrl.text.replaceAll(',', '.')) ?? 0;
    final dias = int.tryParse(diasCtrl.text) ?? 30;
    if (valor <= 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final now = DateTime.now();
    final conta = ContaReceber(
      lojaId: _lojaId!,
      clienteNome: nomeCtrl.text.trim(),
      valor: valor,
      dataVencimento: now.add(Duration(days: dias)),
      dataVenda: now,
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
                color: _warningColor.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warningColor.withValues(alpha:0.5)),
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
                            backgroundColor: c.pago ? _successColor.withValues(alpha:0.2) : _primaryColor.withValues(alpha:0.2),
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
                                  icon: const Icon(Icons.check_circle_outline),
                                  onPressed: () => _marcarPago(c),
                                  tooltip: 'Marcar como pago',
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

