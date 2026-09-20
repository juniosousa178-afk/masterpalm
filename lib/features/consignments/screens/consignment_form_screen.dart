import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_eligibility.dart';
import '../consignment_errors.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import '../consignment_validation.dart';

class ConsignmentFormScreen extends StatefulWidget {
  const ConsignmentFormScreen({
    super.key,
    required this.lojaId,
    this.consignmentId,
    @visibleForTesting this.debugInitialLines,
  });
  final String lojaId;
  final String? consignmentId;
  final List<ConsignmentDraftLine>? debugInitialLines;

  @override
  State<ConsignmentFormScreen> createState() => _ConsignmentFormScreenState();
}

class _ConsignmentFormScreenState extends State<ConsignmentFormScreen> {
  final _notes = TextEditingController();
  StreamSubscription<List<ConsignmentReseller>>? _resellerSub;
  List<ConsignmentReseller> _resellers = [];
  ConsignmentReseller? _reseller;
  final List<ConsignmentDraftLine> _lines = [];
  bool _busy = false;
  bool _loading = true;
  String? _draftId;

  @override
  void initState() {
    super.initState();
    _draftId = widget.consignmentId ?? ConsignmentService.newId();
    if (widget.debugInitialLines != null) {
      _lines.addAll(widget.debugInitialLines!);
    }
    _resellerSub = ConsignmentService.watchResellers(widget.lojaId).listen((items) {
      if (!mounted) return;
      setState(() {
        _resellers = items;
        _loading = false;
        if (_reseller != null) {
          _reseller = items.where((e) => e.resellerId == _reseller!.resellerId).firstOrNull ?? _reseller;
        }
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _resellerSub?.cancel();
    _notes.dispose();
    super.dispose();
  }

  List<ConsignmentReseller> get _selectorItems => consignmentResellerSelectorItems(
        listed: _resellers,
        selected: _reseller,
      );

  Future<void> _addReseller() async {
    final draft = await showDialog<_ResellerDraft>(
      context: context,
      builder: (ctx) => const _ConsignmentResellerCreateDialog(),
    );
    if (draft == null) return;
    if (consignmentResellerNameError(draft.displayName) != null) {
      _toast(const ConsignmentException('INVALID_ARGUMENT', 'Informe o nome do revendedor.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ConsignmentService.createReseller(
        lojaId: widget.lojaId,
        displayName: draft.displayName,
        phone: draft.phone,
        notes: draft.notes,
      );
      if (!mounted) return;
      final id = (res['resellerId'] ?? '').toString();
      final display = (res['displayName'] ?? draft.displayName).toString();
      if (id.isEmpty) {
        _toast(const ConsignmentException('SERVER', 'Revendedor criado sem identificador.'));
        return;
      }
      setState(() {
        _reseller = ConsignmentReseller(
          resellerId: id,
          displayName: display,
          notes: draft.notes,
          phone: draft.phone,
          storeId: widget.lojaId,
        );
      });
    } catch (e) {
      if (!mounted) return;
      _toastReseller(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addProduct() async {
    List<ConsignmentPickerItem> catalog;
    try {
      catalog = await ConsignmentService.loadPickerProducts(widget.lojaId);
    } catch (_) {
      catalog = const [];
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<ConsignmentPickerItem>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final filtered = consignmentPickerVisibleItems(catalog, query: q);
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Disponíveis para consignação', style: MpType.section),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      key: const Key('consignment_product_search'),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar produto',
                      ),
                      onChanged: (v) => setModal(() => q = v),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Nenhum produto disponível para consignação.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final p = filtered[i];
                              return ListTile(
                                key: ValueKey('picker_${p.productId}'),
                                enabled: p.eligible,
                                title: Text(p.name),
                                subtitle: Text(
                                  p.eligible
                                      ? consignmentMoney.format(p.price)
                                      : p.unavailableReason,
                                ),
                                onTap: p.eligible ? () => Navigator.pop(ctx, p) : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (selected == null || !selected.eligible) return;
    var type = selected.stockKind == 'variation' ? 'variation' : 'simple';
    var variation = const ConsignmentVariationKey();
    if (type == 'variation') {
      final picked = await _pickVariation(selected.variacoes);
      if (picked == null) return;
      variation = picked;
    }
    if (!mounted) return;
    setState(() {
      _lines.add(ConsignmentDraftLine(
        productId: selected.productId,
        productName: selected.name,
        productType: type,
        qtySent: 1,
        unitSalePrice: selected.price,
        variationKey: variation,
      ));
    });
  }

  Future<ConsignmentVariationKey?> _pickVariation(Map<String, dynamic> variacoes) async {
    final sizes = variacoes.keys.map((e) => e.toString()).toList();
    if (sizes.isEmpty) return null;
    String? size = sizes.length == 1 ? sizes.first : null;
    String? color;
    List<String> colorsOf(String? s) {
      if (s == null) return const [];
      final cells = variacoes[s];
      if (cells is! Map) return const [];
      return cells.keys.map((e) => e.toString()).where((k) => k != 'custo').toList();
    }
    if (size != null) {
      final colors = colorsOf(size);
      color = colors.length == 1 ? colors.first : null;
    }
    return showDialog<ConsignmentVariationKey>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Variação'),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              final colorKeys = colorsOf(size);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: size,
                    decoration: const InputDecoration(labelText: 'Tamanho'),
                    items: sizes
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setLocal(() {
                      size = v;
                      color = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: colorKeys.contains(color) ? color : null,
                    decoration: const InputDecoration(labelText: 'Cor'),
                    items: colorKeys
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setLocal(() => color = v),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (size == null || color == null) return;
                Navigator.pop(
                  ctx,
                  ConsignmentVariationKey(size: size!, color: color!),
                );
              },
              child: const Text('Usar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _issue() async {
    if (_busy || ConsignmentService.issueInFlight) return;
    if (_reseller == null) {
      _toast(const ConsignmentException('INVALID_ARGUMENT', 'Selecione um revendedor.'));
      return;
    }
    if (_lines.isEmpty) {
      _toast(const ConsignmentException('INVALID_ARGUMENT', 'Adicione ao menos um produto.'));
      return;
    }
    final total = consignmentDraftTotalQty(_lines);
    final potential = consignmentDraftPotential(_lines);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar saída'),
        content: Text(
          'Confirmar saída de $total peças em consignação?\n\n'
          'Total potencial ${consignmentMoney.format(potential.gross)}\n'
          'Comissão ${consignmentMoney.format(potential.commission)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar em consignação')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ConsignmentService.createDraft(
        lojaId: widget.lojaId,
        consignmentId: _draftId!,
        resellerId: _reseller!.resellerId,
        lines: _lines,
        notes: _notes.text.trim(),
      );
      await ConsignmentService.issue(
        lojaId: widget.lojaId,
        consignmentId: _draftId!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(Object e) {
    final msg = e is ConsignmentException ? e.message : ConsignmentException.userMessage('SERVER', e.toString());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toastReseller(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ConsignmentException.resellerUserMessage(e))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final potential = consignmentDraftPotential(_lines);
    final selectorItems = _selectorItems;
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Nova consignação')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (selectorItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Nenhum revendedor cadastrado'),
                  ),
                if (selectorItems.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _reseller?.resellerId,
                    decoration: const InputDecoration(labelText: 'Revendedor'),
                    items: selectorItems
                        .map((r) => DropdownMenuItem(value: r.resellerId, child: Text(r.displayName)))
                        .toList(),
                    onChanged: (id) {
                      setState(() {
                        _reseller = selectorItems.where((e) => e.resellerId == id).firstOrNull;
                      });
                    },
                  ),
                TextButton.icon(
                  onPressed: _busy ? null : _addReseller,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Cadastrar revendedor'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Observações'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Produtos', style: MpType.section),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy ? null : _addProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar'),
                    ),
                  ],
                ),
                for (var i = 0; i < _lines.length; i++) _lineTile(i),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Itens: ${consignmentDraftTotalQty(_lines)}'),
                        Text('Total potencial: ${consignmentMoney.format(potential.gross)}'),
                        Text('Comissão: ${consignmentMoney.format(potential.commission)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _issue,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enviar em consignação'),
                ),
              ],
            ),
    );
  }

  Widget _lineTile(int i) {
    final line = _lines[i];
    return Card(
      child: ListTile(
        title: Text(line.productName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!line.variationKey.isEmpty)
              Text('${line.variationKey.size} ${line.variationKey.color}'.trim()),
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    initialValue: '${line.qtySent}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qtd'),
                    onChanged: (v) {
                      final n = int.tryParse(v) ?? 0;
                      setState(() => line.qtySent = n < 1 ? 1 : n);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    initialValue: line.unitSalePrice.toStringAsFixed(2),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Preço'),
                    onChanged: (v) {
                      setState(() => line.unitSalePrice = double.tryParse(v.replaceAll(',', '.')) ?? line.unitSalePrice);
                    },
                  ),
                ),
              ],
            ),
            DropdownButton<String>(
              value: line.commissionType,
              items: const [
                DropdownMenuItem(value: 'SEM_COMISSAO', child: Text('Sem comissão')),
                DropdownMenuItem(value: 'PERCENTUAL', child: Text('% comissão')),
                DropdownMenuItem(value: 'VALOR_FIXO_POR_UNIDADE', child: Text('Valor fixo/un')),
              ],
              onChanged: (v) => setState(() => line.commissionType = v ?? 'SEM_COMISSAO'),
            ),
            if (line.commissionType != 'SEM_COMISSAO')
              SizedBox(
                width: 96,
                child: TextFormField(
                  initialValue: line.commissionValue.toStringAsFixed(2),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Comissão'),
                  onChanged: (v) {
                    setState(() => line.commissionValue =
                        double.tryParse(v.replaceAll(',', '.')) ?? line.commissionValue);
                  },
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _lines.removeAt(i)),
        ),
      ),
    );
  }
}

class _ResellerDraft {
  const _ResellerDraft({required this.displayName, this.phone = '', this.notes = ''});
  final String displayName;
  final String phone;
  final String notes;
}

class _ConsignmentResellerCreateDialog extends StatefulWidget {
  const _ConsignmentResellerCreateDialog();

  @override
  State<_ConsignmentResellerCreateDialog> createState() => _ConsignmentResellerCreateDialogState();
}

class _ConsignmentResellerCreateDialogState extends State<_ConsignmentResellerCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cadastrar revendedor'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome *'),
                validator: consignmentResellerNameError,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Observação'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              _ResellerDraft(
                displayName: _name.text.trim(),
                phone: _phone.text.trim(),
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
