// lib/screens/financeiro/gastos_fixos_screen.dart
// Cadastro de gastos fixos (sem geracao automatica nesta fase).

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../financeiro/financeiro_constants.dart';
import '../../models/gasto_fixo_mensal.dart';
import '../../services/financeiro_firestore_service.dart';
import '../../services/financeiro_hive_store.dart';
import '../../utils/moeda_input_formatter.dart';

class GastosFixosScreen extends StatefulWidget {
  const GastosFixosScreen({super.key, required this.lojaId});

  final String lojaId;

  @override
  State<GastosFixosScreen> createState() => _GastosFixosScreenState();
}

class _GastosFixosScreenState extends State<GastosFixosScreen> {
  static const Color _primary = Color(0xFF6366F1);

  Box<GastoFixoMensal>? _box;
  bool _loading = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      _box = await FinanceiroHiveStore.openGastosFixosBox(widget.lojaId);
      if (_box == null) {
        throw Exception('Não foi possível abrir gastos fixos.');
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.toString();
        });
      }
    }
  }

  List<GastoFixoMensal> get _lista {
    if (_box == null) return [];
    return _box!.values
        .where((g) => g.lojaId == widget.lojaId)
        .toList()
      ..sort((a, b) => a.descricao.compareTo(b.descricao));
  }

  Future<void> _abrirForm({GastoFixoMensal? item}) async {
    final box = _box;
    if (box == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _GastoFixoDialog(
        lojaId: widget.lojaId,
        item: item,
        onSalvar: (g) async {
          await box.put(g.id, g);
          unawaited(FinanceiroFirestoreService.upsertGastoFixo(g));
        },
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _toggleAtivo(GastoFixoMensal g) async {
    final anterior = g.ativo;
    g.ativo = !anterior;
    try {
      await g.save();
      unawaited(FinanceiroFirestoreService.upsertGastoFixo(g));
    } catch (_) {
      g.ativo = anterior;
    }
    if (mounted) setState(() {});
  }

  Future<void> _excluir(GastoFixoMensal g) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir gasto fixo?'),
        content: Text(g.descricao),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (conf == true && _box != null) {
      final id = g.id;
      final lojaId = widget.lojaId;
      await _box!.delete(id);
      unawaited(
        FinanceiroFirestoreService.deleteGastoFixo(lojaId: lojaId, id: id),
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Gastos fixos mensais'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _box == null ? null : () => _abrirForm(),
        backgroundColor: _primary,
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _erro != null
              ? Center(child: Text(_erro!))
              : RefreshIndicator(
                  color: _primary,
                  onRefresh: _open,
                  child: _lista.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 100),
                            Icon(Icons.event_repeat, size: 56, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Cadastre aluguel, internet, salários etc. '
                                  'A geração automática de lançamentos fica para uma fase futura.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          itemCount: _lista.length,
                          itemBuilder: (_, i) {
                            final g = _lista[i];
                            final moeda = g.valorPadrao == 0
                                ? '0,00'
                                : MoedaInputFormatter.format(g.valorPadrao);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  g.descricao,
                                  style: TextStyle(
                                    decoration: g.ativo
                                        ? null
                                        : TextDecoration.lineThrough,
                                  ),
                                ),
                                subtitle: Text(
                                  'Venc. dia ${g.diaVencimento} · $moeda\n'
                                  '${g.categoria.replaceAll('_', ' ')}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _abrirForm(item: g);
                                    if (v == 'toggle') _toggleAtivo(g);
                                    if (v == 'del') _excluir(g);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Editar'),
                                    ),
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text('Ativar / desativar'),
                                    ),
                                    PopupMenuItem(
                                      value: 'del',
                                      child: Text('Excluir'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _GastoFixoDialog extends StatefulWidget {
  const _GastoFixoDialog({
    required this.lojaId,
    required this.onSalvar,
    this.item,
  });

  final String lojaId;
  final GastoFixoMensal? item;
  final Future<void> Function(GastoFixoMensal g) onSalvar;

  @override
  State<_GastoFixoDialog> createState() => _GastoFixoDialogState();
}

class _GastoFixoDialogState extends State<_GastoFixoDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descCtrl;
  late TextEditingController _valorCtrl;
  late TextEditingController _fornCtrl;
  late TextEditingController _obsCtrl;
  late TextEditingController _centroCtrl;
  late TextEditingController _formaCtrl;
  late TextEditingController _subCtrl;
  late String _categoria;
  late int _dia;
  late bool _ativo;

  @override
  void initState() {
    super.initState();
    final e = widget.item;
    _descCtrl = TextEditingController(text: e?.descricao ?? '');
    _valorCtrl = TextEditingController(
      text: e != null ? MoedaInputFormatter.format(e.valorPadrao) : '',
    );
    _fornCtrl = TextEditingController(text: e?.fornecedor ?? '');
    _obsCtrl = TextEditingController(text: e?.observacao ?? '');
    _centroCtrl = TextEditingController(text: e?.centroCusto ?? '');
    _formaCtrl = TextEditingController(text: e?.formaPagamentoPadrao ?? '');
    _subCtrl = TextEditingController(text: e?.subcategoria ?? '');
    _categoria = financeiroCategoriaOuPadrao(
        e?.categoria.isNotEmpty == true ? e!.categoria : '');
    _dia = (e?.diaVencimento ?? 10).clamp(1, 28);
    _ativo = e?.ativo ?? true;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _valorCtrl.dispose();
    _fornCtrl.dispose();
    _obsCtrl.dispose();
    _centroCtrl.dispose();
    _formaCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Novo gasto fixo' : 'Editar gasto fixo'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descrição *',
                  border: OutlineInputBorder(),
                ),
                validator: (s) =>
                    (s == null || s.trim().isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _valorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor padrão *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [MoedaInputFormatter()],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _categoria,
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  border: OutlineInputBorder(),
                ),
                items: kFinanceiroCategoriasPadrao
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.categoria,
                        child: Text(c.categoria.replaceAll('_', ' ')),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _categoria = v ?? _categoria),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _subCtrl,
                decoration: const InputDecoration(
                  labelText: 'Subcategoria',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Dia vencimento:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _dia,
                    items: List.generate(
                      28,
                      (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                    ),
                    onChanged: (v) =>
                        setState(() => _dia = (v ?? _dia).clamp(1, 28)),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativo'),
                value: _ativo,
                onChanged: (v) => setState(() => _ativo = v),
              ),
              TextFormField(
                controller: _formaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento padrão',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _fornCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fornecedor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _centroCtrl,
                decoration: const InputDecoration(
                  labelText: 'Centro de custo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _obsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final valor = MoedaInputFormatter.parse(_valorCtrl.text);
            if (valor < 0) return;
            final id = widget.item?.id ?? const Uuid().v4();
            final g = GastoFixoMensal(
              id: id,
              lojaId: widget.lojaId,
              descricao: _descCtrl.text.trim(),
              valorPadrao: valor,
              categoria: _categoria,
              subcategoria: _subCtrl.text.trim(),
              diaVencimento: _dia,
              ativo: _ativo,
              formaPagamentoPadrao: _formaCtrl.text.trim(),
              fornecedor: _fornCtrl.text.trim(),
              observacao: _obsCtrl.text.trim(),
              centroCusto: _centroCtrl.text.trim(),
            );
            await widget.onSalvar(g);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
