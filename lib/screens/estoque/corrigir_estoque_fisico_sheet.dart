// Wizard: Corrigir estoque físico (contagem absoluta, sem editar qty bruta).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/firestore_paths.dart';
import '../../core/produto_stock_revision.dart';
import '../../models/produto.dart';
import '../../services/movimentacao_estoque_service.dart';
import '../../services/stock_catalog_backend_service.dart';

const String kPhysicalReconciliationConflictMessage =
    'Este estoque foi alterado enquanto você conferia. Atualize os dados e confirme novamente.';
const String kPhysicalReconciliationPendingMessage =
    'Existe uma movimentação de estoque em processamento. Aguarde a conclusão antes de corrigir o estoque.';
const String kPhysicalReconciliationComboMessage =
    'Reconciliação física de estoque não está disponível para produtos combo.';

enum _ProductStructure { simple, variation, grade, noControl }

class CorrigirEstoqueFisicoSheet extends StatefulWidget {
  const CorrigirEstoqueFisicoSheet({
    required this.produto,
    required this.lojaId,
    super.key,
  });

  final Produto produto;
  final String lojaId;

  static Future<bool?> open(
    BuildContext context, {
    required Produto produto,
    required String lojaId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CorrigirEstoqueFisicoSheet(
        produto: produto,
        lojaId: lojaId,
      ),
    );
  }

  @override
  State<CorrigirEstoqueFisicoSheet> createState() =>
      _CorrigirEstoqueFisicoSheetState();
}

class _CellRow {
  _CellRow({required this.size, required this.color, required this.qtyCtrl});
  String size;
  String color;
  final TextEditingController qtyCtrl;
}

class _CorrigirEstoqueFisicoSheetState extends State<CorrigirEstoqueFisicoSheet> {
  bool _loadingRemote = true;
  bool _saving = false;
  String? _error;
  int _expectedRevision = 0;
  int _beforeQty = 0;
  String? _remoteStockKind;
  bool _needsStructure = false;
  bool _activateStockControl = false;
  _ProductStructure? _structure;
  final _physicalQtyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final List<_CellRow> _cells = [];
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _physicalQtyCtrl.dispose();
    _noteCtrl.dispose();
    for (final c in _cells) {
      c.qtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingRemote = true;
      _error = null;
    });
    try {
      if (widget.produto.ehCombo) {
        setState(() {
          _loadingRemote = false;
          _error = kPhysicalReconciliationComboMessage;
        });
        return;
      }
      if (hasPendingStockMutation(widget.produto)) {
        setState(() {
          _loadingRemote = false;
          _error = kPhysicalReconciliationPendingMessage;
        });
        return;
      }

      final id = widget.produto.idFirebase.trim().isNotEmpty
          ? widget.produto.idFirebase
          : '';
      if (id.isEmpty) {
        setState(() {
          _loadingRemote = false;
          _error = 'Produto sem identificador remoto.';
        });
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      final remote = snap.data() ?? <String, dynamic>{};
      final rev = (remote['stockRevision'] as num?)?.toInt() ??
          widget.produto.stockRevision;
      final qty = (remote['quantidade'] as num?)?.toInt() ??
          widget.produto.quantidade;
      final kind = (remote['stockKind'] ?? '').toString().trim().toLowerCase();
      final remoteKind = kind.isEmpty ? null : kind;

      if (remoteKind == 'combo' || widget.produto.ehCombo) {
        setState(() {
          _loadingRemote = false;
          _error = kPhysicalReconciliationComboMessage;
        });
        return;
      }

      _expectedRevision = rev;
      _beforeQty = qty;
      _remoteStockKind = remoteKind;
      _needsStructure = remoteKind == null;

      if (remoteKind == 'simple' ||
          (remoteKind == null && !widget.produto.usaVariacoes)) {
        _structure = _ProductStructure.simple;
        _physicalQtyCtrl.text = qty.toString();
      } else if (remoteKind == 'variation' || widget.produto.usaVariacoes) {
        _structure = _ProductStructure.grade;
        _seedCellsFrom(remote, widget.produto);
      } else {
        _structure = null;
      }

      setState(() => _loadingRemote = false);
    } catch (e) {
      setState(() {
        _loadingRemote = false;
        _error = 'Não foi possível carregar o estoque remoto.';
      });
    }
  }

  void _seedCellsFrom(Map<String, dynamic> remote, Produto p) {
    for (final c in _cells) {
      c.qtyCtrl.dispose();
    }
    _cells.clear();

    final variacoes = remote['variacoes'] is Map
        ? Map<String, dynamic>.from(remote['variacoes'] as Map)
        : (p.variacoes != null ? Map<String, dynamic>.from(p.variacoes!) : null);

    if (variacoes != null && variacoes.isNotEmpty) {
      for (final sizeEntry in variacoes.entries) {
        final size = sizeEntry.key.toString();
        final colors = sizeEntry.value;
        if (colors is! Map) continue;
        for (final colorEntry in colors.entries) {
          final color = colorEntry.key.toString();
          final raw = colorEntry.value;
          final q = raw is Map
              ? 0
              : (raw as num?)?.toInt() ?? 0;
          _cells.add(_CellRow(
            size: size,
            color: color,
            qtyCtrl: TextEditingController(text: q.toString()),
          ));
        }
      }
    }

    // Legacy metadata suggestions only — qty must be entered (default 0).
    if (_cells.isEmpty) {
      final sizes = <String>{
        ...((remote['tamanhos'] as List?) ?? p.tamanhos)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty),
        ...p.estoquePorTamanho.keys,
      };
      final colors = <String>{
        ...((remote['cores'] as List?) ?? p.cores)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty),
      };
      if (colors.isEmpty) colors.add('sem-cor');
      if (sizes.isEmpty) sizes.add('sem-tamanho');
      for (final size in sizes) {
        for (final color in colors) {
          _cells.add(_CellRow(
            size: size,
            color: color,
            qtyCtrl: TextEditingController(text: '0'),
          ));
        }
      }
    }
  }

  int get _physicalTotal {
    if (_structure == _ProductStructure.simple) {
      return int.tryParse(_physicalQtyCtrl.text.trim()) ?? 0;
    }
    var sum = 0;
    for (final c in _cells) {
      final q = int.tryParse(c.qtyCtrl.text.trim()) ?? 0;
      if (q > 0) sum += q;
    }
    return sum;
  }

  List<Map<String, dynamic>> get _cellsPayload {
    return _cells
        .map((c) => {
              'size': c.size.trim(),
              'color': c.color.trim(),
              'quantity': int.tryParse(c.qtyCtrl.text.trim()) ?? 0,
            })
        .toList();
  }

  List<String> get _changedCellLabels {
    // Show all cells as physical → new (absolute).
    return _cells
        .map((c) {
          final q = int.tryParse(c.qtyCtrl.text.trim()) ?? 0;
          return '${c.size} ${c.color}: → $q';
        })
        .toList();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_structure == _ProductStructure.noControl) {
      setState(() {
        _error =
            'NO_CONTROL não cria estoque controlado. Ative o controle de estoque e informe a contagem.';
      });
      return;
    }
    if (_needsStructure && _structure == null) {
      setState(() => _error = 'Selecione a estrutura do produto.');
      return;
    }
    if (_needsStructure &&
        _structure != _ProductStructure.simple &&
        _structure != _ProductStructure.variation &&
        _structure != _ProductStructure.grade) {
      setState(() => _error = 'Selecione a estrutura do produto.');
      return;
    }

    // Color identity must be confirmed for each cell.
    if (_structure != _ProductStructure.simple) {
      for (final c in _cells) {
        if (c.color.trim().isEmpty) {
          setState(() =>
              _error = 'Confirme a cor de cada variação (não inventamos cor).');
          return;
        }
      }
    }

    if (!_confirming) {
      setState(() => _confirming = true);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final operationId = newStockOperationId();
    final structureWire = switch (_structure) {
      _ProductStructure.simple => 'simple',
      _ProductStructure.variation => 'variation',
      _ProductStructure.grade => 'grade',
      _ => null,
    };

    final reconciliation = <String, dynamic>{
      'physicalCountConfirmed': true,
      'reason': 'Estoque corrigido por contagem física',
      if (_noteCtrl.text.trim().isNotEmpty)
        'operatorNote': _noteCtrl.text.trim(),
      if (_needsStructure || _activateStockControl)
        'productStructure': structureWire,
      if (_activateStockControl) 'activateStockControl': true,
      if (_structure == _ProductStructure.simple)
        'physicalQty': int.tryParse(_physicalQtyCtrl.text.trim()) ?? 0
      else
        'cells': _cellsPayload,
    };

    try {
      final result = await StockCatalogBackendService.command(
        lojaId: widget.lojaId,
        operationId: operationId,
        kind: 'physicalReconciliation',
        items: [
          {
            'productId': widget.produto.idFirebase,
            'expectedRevision': _expectedRevision,
          }
        ],
        reconciliation: reconciliation,
      );

      final products = result['products'];
      Map<String, dynamic>? row;
      if (products is List && products.isNotEmpty && products.first is Map) {
        row = Map<String, dynamic>.from(products.first as Map);
      }

      final afterQty =
          (row?['quantidade'] as num?)?.toInt() ?? _physicalTotal;
      final afterRev = (row?['stockRevision'] as num?)?.toInt();
      final delta = afterQty - _beforeQty;

      // Hydrate local from authoritative response.
      widget.produto.quantidade = afterQty;
      if (afterRev != null) widget.produto.stockRevision = afterRev;
      if (row != null) {
        if (row['variacoes'] is Map) {
          widget.produto.variacoes =
              Map<String, dynamic>.from(row['variacoes'] as Map);
        }
        if (row['estoquePorTamanho'] is Map) {
          widget.produto.estoquePorTamanho = {
            for (final e in (row['estoquePorTamanho'] as Map).entries)
              e.key.toString(): (e.value as num?)?.toInt() ?? 0,
          };
        }
        if (row['tamanhos'] is List) {
          widget.produto.tamanhos =
              (row['tamanhos'] as List).map((e) => e.toString()).toList();
        }
        if (row['cores'] is List) {
          widget.produto.cores =
              (row['cores'] as List).map((e) => e.toString()).toList();
        }
      }
      widget.produto.updatedAt = DateTime.now();
      await widget.produto.save();

      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'App';
      await MovimentacaoEstoqueService.registrar(
        lojaId: widget.lojaId,
        produtoId: widget.produto.idFirebase,
        produtoNome: widget.produto.nome,
        tipo: delta >= 0 ? 'entrada' : 'saida',
        quantidade: delta.abs(),
        motivo: 'Estoque corrigido por contagem física',
        usuario: uid,
        beforeQty: _beforeQty,
        afterQty: afterQty,
        delta: delta,
        cellsChanged: _structure == _ProductStructure.simple
            ? null
            : _cellsPayload,
        stockOperationId: operationId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      final code = e.code;
      final msg = (e.message ?? '').toString();
      String friendly;
      if (code == 'aborted' || msg.contains('alterado enquanto')) {
        friendly = kPhysicalReconciliationConflictMessage;
      } else if (msg.contains('processamento') || msg.contains('pending')) {
        friendly = kPhysicalReconciliationPendingMessage;
      } else if (msg.toLowerCase().contains('combo')) {
        friendly = kPhysicalReconciliationComboMessage;
      } else {
        friendly = msg.isNotEmpty ? msg : 'Falha ao corrigir estoque físico.';
      }
      setState(() {
        _saving = false;
        _confirming = false;
        _error = friendly;
      });
      if (code == 'aborted') {
        await _bootstrap();
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _confirming = false;
        _error = 'Falha ao corrigir estoque físico.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (context, controller) {
          return Material(
            color: const Color(0xFFF8FAFC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Corrigir estoque físico',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loadingRemote
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            Text(
                              widget.produto.nome,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Estoque atual (sistema): $_beforeQty',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                  ),
                                ),
                              ),
                            ],
                            if (_error == kPhysicalReconciliationComboMessage ||
                                _error ==
                                    kPhysicalReconciliationPendingMessage)
                              const SizedBox.shrink()
                            else ...[
                              if (_needsStructure) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Estrutura do produto',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Esta ação também definirá a estrutura de estoque deste produto.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final s in _ProductStructure.values)
                                      ChoiceChip(
                                        label: Text(switch (s) {
                                          _ProductStructure.simple => 'SIMPLE',
                                          _ProductStructure.variation =>
                                            'VARIATION',
                                          _ProductStructure.grade => 'GRADE',
                                          _ProductStructure.noControl =>
                                            'NO_CONTROL',
                                        }),
                                        selected: _structure == s,
                                        onSelected: _saving
                                            ? null
                                            : (_) => setState(() {
                                                  _structure = s;
                                                  _confirming = false;
                                                  if (s ==
                                                          _ProductStructure
                                                              .variation ||
                                                      s ==
                                                          _ProductStructure
                                                              .grade) {
                                                    if (_cells.isEmpty) {
                                                      _seedCellsFrom(
                                                        {},
                                                        widget.produto,
                                                      );
                                                    }
                                                  }
                                                }),
                                      ),
                                  ],
                                ),
                                if (_remoteStockKind == null) ...[
                                  const SizedBox(height: 8),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Ativar controle de estoque'),
                                    value: _activateStockControl,
                                    onChanged: _saving
                                        ? null
                                        : (v) => setState(
                                              () => _activateStockControl = v,
                                            ),
                                  ),
                                ],
                              ],
                              if (_structure == _ProductStructure.simple) ...[
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _physicalQtyCtrl,
                                  enabled: !_saving,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Contagem física',
                                    border: OutlineInputBorder(),
                                    helperText:
                                        'Informe a quantidade real contada. Zero é válido.',
                                  ),
                                  onChanged: (_) =>
                                      setState(() => _confirming = false),
                                ),
                              ],
                              if (_structure == _ProductStructure.variation ||
                                  _structure == _ProductStructure.grade) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Contagem por célula (canónica)',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Não informe um total para distribuir. Cada célula precisa da quantidade física.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (var i = 0; i < _cells.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            initialValue: _cells[i].size,
                                            enabled: !_saving,
                                            decoration: const InputDecoration(
                                              labelText: 'Tamanho',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            onChanged: (v) {
                                              _cells[i].size = v;
                                              _confirming = false;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextFormField(
                                            initialValue: _cells[i].color,
                                            enabled: !_saving,
                                            decoration: const InputDecoration(
                                              labelText: 'Cor',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            onChanged: (v) {
                                              _cells[i].color = v;
                                              setState(() => _confirming = false);
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 72,
                                          child: TextField(
                                            controller: _cells[i].qtyCtrl,
                                            enabled: !_saving,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Qtd',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            onChanged: (_) => setState(
                                                () => _confirming = false),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                TextButton.icon(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() {
                                            _cells.add(_CellRow(
                                              size: '',
                                              color: 'sem-cor',
                                              qtyCtrl: TextEditingController(
                                                text: '0',
                                              ),
                                            ));
                                            _confirming = false;
                                          }),
                                  icon: const Icon(Icons.add),
                                  label: const Text(
                                    'Adicionar opção física',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextField(
                                controller: _noteCtrl,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  labelText: 'Nota do operador (opcional)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              if (_confirming) ...[
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Produto: ${widget.produto.nome}'),
                                      Text('Estoque atual: $_beforeQty'),
                                      Text(
                                          'Contagem física: $_physicalTotal'),
                                      Text('Novo estoque: $_physicalTotal'),
                                      Text(
                                        'Diferença: ${_physicalTotal - _beforeQty}',
                                      ),
                                      if (_structure !=
                                          _ProductStructure.simple) ...[
                                        const SizedBox(height: 8),
                                        const Text('Células:'),
                                        for (final line in _changedCellLabels)
                                          Text(line,
                                              style:
                                                  const TextStyle(fontSize: 12)),
                                      ],
                                      if (_needsStructure) ...[
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Esta ação também definirá a estrutura de estoque deste produto.',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _saving ||
                                        _error ==
                                            kPhysicalReconciliationComboMessage
                                    ? null
                                    : _submit,
                                child: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _confirming
                                            ? 'Confirmar correção de estoque'
                                            : 'Revisar correção',
                                      ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
