import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/hive_box_names.dart';
import '../../../design_system/mp_tokens.dart';
import '../../../models/produto.dart';
import '../consignment_errors.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import '../consignment_validation.dart';

class ConsignmentFormScreen extends StatefulWidget {
  const ConsignmentFormScreen({super.key, required this.lojaId, this.consignmentId});
  final String lojaId;
  final String? consignmentId;

  @override
  State<ConsignmentFormScreen> createState() => _ConsignmentFormScreenState();
}

class _ConsignmentFormScreenState extends State<ConsignmentFormScreen> {
  final _notes = TextEditingController();
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
    ConsignmentService.watchResellers(widget.lojaId).listen((items) {
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
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addReseller() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo revendedor'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Nome'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await ConsignmentService.createReseller(
        lojaId: widget.lojaId,
        displayName: name.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _reseller = ConsignmentReseller(
          resellerId: (res['resellerId'] ?? '').toString(),
          displayName: name.text.trim(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addProduct() async {
    final boxName = HiveBoxNames.produtos(widget.lojaId);
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<Produto>(boxName);
    }
    final box = Hive.box<Produto>(boxName);
    final produtos = box.values.toList();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final filtered = produtos.where((p) {
              if (q.isEmpty) return true;
              return p.nome.toLowerCase().contains(q.toLowerCase());
            }).take(80).toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar produto',
                      ),
                      onChanged: (v) => setModal(() => q = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return ListTile(
                          title: Text(p.nome),
                          subtitle: Text(consignmentMoney.format(p.precoFinal)),
                          onTap: () => Navigator.pop(ctx, p),
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
    if (selected == null) return;
    if (consignmentProductIsCombo(selected)) {
      _toast(const ConsignmentException('PRODUCT_STATE_UNSAFE',
          'Combos não são suportados no consignado.'));
      return;
    }
    if (consignmentProductIsGrade(selected)) {
      _toast(const ConsignmentException(
          'CONSIGNMENT_GRADE_NOT_SUPPORTED',
          ConsignmentException.userMessage('CONSIGNMENT_GRADE_NOT_SUPPORTED')));
      return;
    }
    final productId = selected.idFirebase.trim().isNotEmpty
        ? selected.idFirebase.trim()
        : selected.key.toString();
    if (productId.isEmpty) {
      _toast(const ConsignmentException('PRODUCT_NOT_FOUND', 'Produto sem ID canônico.'));
      return;
    }
    var type = 'simple';
    var variation = const ConsignmentVariationKey();
    if (selected.usaVariacoes) {
      type = 'variation';
      final picked = await _pickVariation(selected);
      if (picked == null) return;
      variation = picked;
    }
    if (!mounted) return;
    setState(() {
      _lines.add(ConsignmentDraftLine(
        productId: productId,
        productName: selected.nome,
        productType: type,
        qtySent: 1,
        unitSalePrice: selected.precoFinal,
        variationKey: variation,
      ));
    });
  }

  Future<ConsignmentVariationKey?> _pickVariation(Produto p) async {
    final sizes = p.variacoes?.keys.map((e) => e.toString()).toList() ?? [];
    if (sizes.isEmpty) return null;
    String? size = sizes.length == 1 ? sizes.first : null;
    String? color;
    if (size != null) {
      final colors = ((p.variacoes![size] as Map?)?.keys.map((e) => e.toString()).toList() ?? []);
      color = colors.length == 1 ? colors.first : null;
    }
    return showDialog<ConsignmentVariationKey>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Variação'),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              final colorKeys = size == null
                  ? const <String>[]
                  : ((p.variacoes![size] as Map?)?.keys.map((e) => e.toString()).toList() ?? []);
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

  @override
  Widget build(BuildContext context) {
    final potential = consignmentDraftPotential(_lines);
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Nova consignação')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: _reseller?.resellerId,
                  decoration: const InputDecoration(labelText: 'Revendedor'),
                  items: _resellers
                      .map((r) => DropdownMenuItem(value: r.resellerId, child: Text(r.displayName)))
                      .toList(),
                  onChanged: (id) {
                    setState(() {
                      _reseller = _resellers.where((e) => e.resellerId == id).firstOrNull;
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
