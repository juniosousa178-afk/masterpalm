// lib/screens/nova_venda/finalizar_confirmacao_dialog.dart
// Dialog de confirmação ao finalizar venda: pagamento split, troco e resumo

import 'package:flutter/material.dart';
import '../../utils/moeda_input_formatter.dart';
import '../../widgets/moeda_text_field.dart';

/// Resultado ao confirmar o dialog
class FinalizarVendaResult {
  final List<Map<String, dynamic>> pagamentos;
  final double trocoTotal;
  final bool isFiado;
  final int diasVencimento;
  final int quantidadeParcelasFiado;
  final int intervaloParcelasDias;

  FinalizarVendaResult({
    required this.pagamentos,
    required this.trocoTotal,
    this.isFiado = false,
    this.diasVencimento = 30,
    this.quantidadeParcelasFiado = 1,
    this.intervaloParcelasDias = 30,
  });
}

/// Dialog de confirmação de venda com:
/// - Resumo dos produtos e total
/// - Split de pagamento (Pix, Cartão, Dinheiro)
/// - Valor recebido e troco para pagamento em dinheiro
class FinalizarVendaConfirmacaoDialog extends StatefulWidget {
  final double total;
  final List<Map<String, dynamic>> resumoProdutos;
  final double frete;
  final double desconto;
  final List<Map<String, dynamic>>? initialPagamentos;
  final VoidCallback onCancelar;
  final void Function(FinalizarVendaResult result) onConfirmar;

  const FinalizarVendaConfirmacaoDialog({
    super.key,
    required this.total,
    required this.resumoProdutos,
    this.frete = 0,
    this.desconto = 0,
    this.initialPagamentos,
    required this.onCancelar,
    required this.onConfirmar,
  });

  static Future<FinalizarVendaResult?> show(
    BuildContext context, {
    required double total,
    required List<Map<String, dynamic>> resumoProdutos,
    double frete = 0,
    double desconto = 0,
    List<Map<String, dynamic>>? initialPagamentos,
  }) async {
    return showDialog<FinalizarVendaResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogHolder(
        total: total,
        resumoProdutos: resumoProdutos,
        frete: frete,
        desconto: desconto,
        initialPagamentos: initialPagamentos,
      ),
    );
  }

  @override
  State<FinalizarVendaConfirmacaoDialog> createState() =>
      _FinalizarVendaConfirmacaoDialogState();
}

class _DialogHolder extends StatelessWidget {
  final double total;
  final List<Map<String, dynamic>> resumoProdutos;
  final double frete;
  final double desconto;
  final List<Map<String, dynamic>>? initialPagamentos;

  const _DialogHolder({
    required this.total,
    required this.resumoProdutos,
    required this.frete,
    required this.desconto,
    this.initialPagamentos,
  });

  @override
  Widget build(BuildContext context) {
    return FinalizarVendaConfirmacaoDialog(
      total: total,
      resumoProdutos: resumoProdutos,
      frete: frete,
      desconto: desconto,
      initialPagamentos: initialPagamentos,
      onCancelar: () => Navigator.pop(context),
      onConfirmar: (r) => Navigator.pop(context, r),
    );
  }
}

class _FinalizarVendaConfirmacaoDialogState
    extends State<FinalizarVendaConfirmacaoDialog> {
  late List<Map<String, dynamic>> _pagamentos;
  final List<TextEditingController> _valorControllers = [];
  final List<TextEditingController> _valorRecebidoControllers = [];
  bool _vendaFiada = false;
  final TextEditingController _diasVencimentoController = TextEditingController(text: '30');
  final TextEditingController _quantidadeParcelasController = TextEditingController(text: '1');
  final TextEditingController _intervaloParcelasController = TextEditingController(text: '30');
  bool _fiadoParcelado = false;

  @override
  void initState() {
    super.initState();
    // Preserva a seleção do formulário principal (Pix/Dinheiro/Cartão)
    final init = widget.initialPagamentos;
    if (init != null && init.isNotEmpty) {
      double soma = 0;
      for (final p in init) {
        final v = (p['valor'] is num) ? (p['valor'] as num).toDouble() : 0.0;
        soma += v;
      }
      final totalVal = widget.total;
      _pagamentos = init.asMap().entries.map((entry) {
        final p = entry.value;
        final forma = (p['forma'] ?? 'Pix').toString();
        final val = (p['valor'] is num) ? (p['valor'] as num).toDouble() : 0.0;
        // Preserva o split. Só coloca total no primeiro quando NADA foi preenchido (soma == 0)
        final valorFinal = (soma >= totalVal - 0.01 || soma > 0)
            ? val
            : (entry.key == 0 ? totalVal : 0.0);
        return {
          'forma': forma,
          'valor': valorFinal,
          'valorRecebido': null,
        };
      }).toList();
      if (soma < 0.01 && _pagamentos.isNotEmpty) {
        _pagamentos[0]['valor'] = totalVal;
      }
      for (final p in _pagamentos) {
        final v = (p['valor'] as num?)?.toDouble() ?? 0.0;
        _valorControllers.add(TextEditingController(text: MoedaInputFormatter.format(v)));
        _valorRecebidoControllers.add(TextEditingController());
      }
    } else {
      _pagamentos = [
        {'forma': 'Pix', 'valor': widget.total, 'valorRecebido': null}
      ];
      _valorControllers.add(TextEditingController(
        text: MoedaInputFormatter.format(widget.total),
      ));
      _valorRecebidoControllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _diasVencimentoController.dispose();
    _quantidadeParcelasController.dispose();
    _intervaloParcelasController.dispose();
    for (final c in _valorControllers) {
      c.dispose();
    }
    for (final c in _valorRecebidoControllers) {
      c.dispose();
    }
    super.dispose();
  }

  double _somarPagamentos() {
    return _pagamentos.fold(0.0, (acc, p) {
      final v = p['valor'];
      if (v is num) return acc + v.toDouble();
      return acc + (double.tryParse(v?.toString() ?? '') ?? 0.0);
    });
  }

  double _calcularTrocoTotal() {
    double troco = 0;
    for (var i = 0; i < _pagamentos.length; i++) {
      if ((_pagamentos[i]['forma'] ?? '') == 'Dinheiro') {
        final vr = _valorRecebidoControllers.length > i
            ? MoedaInputFormatter.parse(
                _valorRecebidoControllers[i].text,
              )
            : 0.0;
        final valor = (_pagamentos[i]['valor'] as num?)?.toDouble() ?? 0.0;
        if (vr > valor) troco += vr - valor;
      }
    }
    return troco;
  }

  bool get _valorOk {
    final soma = _somarPagamentos();
    if (_vendaFiada) {
      if (soma > widget.total + 0.01) return false;
      final saldoFiado = widget.total - soma;
      if (saldoFiado > 0.01) {
        final dias = int.tryParse(_diasVencimentoController.text.trim()) ?? 0;
        return dias >= 1;
      }
      return true;
    }
    return (soma - widget.total).abs() < 0.01;
  }

  void _adicionarForma() {
    setState(() {
      _pagamentos.add({'forma': 'Pix', 'valor': 0.0, 'valorRecebido': null});
      _valorControllers.add(TextEditingController());
      _valorRecebidoControllers.add(TextEditingController());
    });
  }

  void _removerForma(int index) {
    if (_pagamentos.length <= 1) return;
    setState(() {
      _valorControllers[index].dispose();
      _valorRecebidoControllers[index].dispose();
      _valorControllers.removeAt(index);
      _valorRecebidoControllers.removeAt(index);
      _pagamentos.removeAt(index);
    });
  }

  void _preencherComTotal() {
    if (_pagamentos.isEmpty) return;
    _pagamentos[0]['valor'] = widget.total;
    _valorControllers[0].text = MoedaInputFormatter.format(widget.total);
    _valorControllers[0].selection = TextSelection.collapsed(
      offset: _valorControllers[0].text.length,
    );
    setState(() {});
  }

  void _confirmar() {
    if (!_valorOk) return;

    final pagamentosFinais = <Map<String, dynamic>>[];
    if (!_vendaFiada || _somarPagamentos() > 0.01) {
      for (var i = 0; i < _pagamentos.length; i++) {
        final v = MoedaInputFormatter.parse(_valorControllers[i].text);
        if (v <= 0) continue;
        pagamentosFinais.add({
          'forma': _pagamentos[i]['forma'],
          'valor': v,
        });
      }
    }

    if (_vendaFiada) {
      final dias = int.tryParse(_diasVencimentoController.text.trim()) ?? 30;
      final qtdParcelas = _fiadoParcelado
          ? (int.tryParse(_quantidadeParcelasController.text.trim()) ?? 1).clamp(1, 48)
          : 1;
      final intervaloDias = _fiadoParcelado
          ? (int.tryParse(_intervaloParcelasController.text.trim()) ?? 30).clamp(1, 120)
          : 30;
      widget.onConfirmar(FinalizarVendaResult(
        pagamentos: pagamentosFinais,
        trocoTotal: _calcularTrocoTotal(),
        isFiado: true,
        diasVencimento: dias.clamp(1, 365),
        quantidadeParcelasFiado: qtdParcelas,
        intervaloParcelasDias: intervaloDias,
      ));
      return;
    }

    widget.onConfirmar(FinalizarVendaResult(
      pagamentos: pagamentosFinais,
      trocoTotal: _calcularTrocoTotal(),
    ));
  }

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  List<Map<String, dynamic>> _calcularPreviewParcelas() {
    final totalPago = _somarPagamentos();
    final saldoFiado = (widget.total - totalPago).clamp(0.0, double.infinity);
    if (saldoFiado < 0.01) return [];
    final qtd = (int.tryParse(_quantidadeParcelasController.text.trim()) ?? 1).clamp(1, 48);
    final intervalo = (int.tryParse(_intervaloParcelasController.text.trim()) ?? 30).clamp(1, 120);
    final primeiroVenc = (int.tryParse(_diasVencimentoController.text.trim()) ?? 30).clamp(1, 365);
    final totalCentavos = (saldoFiado * 100).round();
    final valorBase = totalCentavos ~/ qtd;
    final resto = totalCentavos % qtd;
    final hoje = DateTime.now();
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < qtd; i++) {
      final cents = valorBase + (i < resto ? 1 : 0);
      final data = hoje.add(Duration(days: primeiroVenc + (i * intervalo)));
      out.add({
        'indice': i + 1,
        'valor': cents / 100.0,
        'data': data,
      });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final totalPago = _somarPagamentos();
    final troco = _calcularTrocoTotal();
    final falta = widget.total - totalPago;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Confirmar venda'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Resumo produtos
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resumo',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.resumoProdutos.take(5).map((p) {
                    final nome = (p['produto'] ?? '').toString();
                    final qtd = (p['quantidade'] ?? 1) as int;
                    final preco = (p['preco'] ?? 0.0) as double;
                    final subtotal = preco * qtd;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$qtd x $nome',
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            'R\$ ${_fmt2(subtotal)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (widget.resumoProdutos.length > 5)
                    Text(
                      '... e mais ${widget.resumoProdutos.length - 5} itens',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  if (widget.frete > 0 || widget.desconto > 0) ...[
                    const Divider(height: 16),
                    if (widget.frete > 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Frete', style: TextStyle(fontSize: 13)),
                          Text(
                            'R\$ ${_fmt2(widget.frete)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    if (widget.desconto > 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Desconto',
                            style: TextStyle(fontSize: 13, color: Colors.green[700]),
                          ),
                          Text(
                            '-R\$ ${_fmt2(widget.desconto)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                  ],
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'R\$ ${_fmt2(widget.total)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Venda fiada
            CheckboxListTile(
              value: _vendaFiada,
              onChanged: (v) => setState(() => _vendaFiada = v ?? false),
              title: const Text('Venda fiada (conta a receber)'),
              subtitle: _vendaFiada
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          TextField(
                            controller: _diasVencimentoController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: '1º vencimento em (dias)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _fiadoParcelado,
                            onChanged: (v) => setState(() => _fiadoParcelado = v),
                            title: const Text('Dividir em parcelas'),
                          ),
                          if (_fiadoParcelado) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _quantidadeParcelasController,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: 'Parcelas',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _intervaloParcelasController,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: 'Intervalo (dias)',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                border: Border.all(color: Colors.blue.shade100),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _calcularPreviewParcelas().take(6).map((p) {
                                  final data = p['data'] as DateTime;
                                  return Text(
                                    '${p['indice']}ª: R\$ ${_fmt2(p['valor'] as num)} - ${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}',
                                    style: const TextStyle(fontSize: 12),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 16),

            // Formas de pagamento (também quando fiado — pagamento misto)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _vendaFiada ? 'Pagamento agora (opcional)' : 'Formas de pagamento',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!_vendaFiada)
                  TextButton.icon(
                    onPressed: _preencherComTotal,
                    icon: const Icon(Icons.touch_app, size: 18),
                    label: const Text('Preencher total'),
                  ),
              ],
            ),
            if (_vendaFiada && falta > 0.01)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Saldo fiado: R\$ ${_fmt2(falta)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
            const SizedBox(height: 8),

            ..._pagamentos.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              final isDinheiro = (p['forma'] ?? '') == 'Dinheiro';
              final valorPag = MoedaInputFormatter.parse(
                _valorControllers.length > i ? _valorControllers[i].text : '',
              );
              final valorRec = isDinheiro && _valorRecebidoControllers.length > i
                  ? MoedaInputFormatter.parse(_valorRecebidoControllers[i].text)
                  : 0.0;
              final trocoItem = isDinheiro && valorRec > valorPag ? valorRec - valorPag : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: p['forma'],
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: const ['Pix', 'Dinheiro', 'Cartão']
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(
                              () => _pagamentos[i]['forma'] = v ?? 'Pix',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: MoedaTextField(
                            controller: _valorControllers[i],
                            labelText: 'Valor',
                            onChanged: (value) {
                              _pagamentos[i]['valor'] = value;
                              setState(() {});
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: _pagamentos.length > 1
                              ? () => _removerForma(i)
                              : null,
                          icon: Icon(
                            Icons.remove_circle,
                            color: _pagamentos.length > 1
                                ? Colors.red
                                : Colors.grey,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                    if (isDinheiro && valorPag > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: MoedaTextField(
                              controller: _valorRecebidoControllers[i],
                              labelText: 'Valor recebido (nota)',
                              hintText: 'Ex: 50,00',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          if (trocoItem > 0) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                'Troco: R\$ ${_fmt2(trocoItem)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),

            TextButton.icon(
              onPressed: _adicionarForma,
              icon: const Icon(Icons.add, size: 18, color: Colors.green),
              label: const Text(
                'Adicionar forma de pagamento',
                style: TextStyle(color: Colors.green),
              ),
            ),

            const SizedBox(height: 12),

            // Status pagamento
            if (!_vendaFiada && falta > 0.01)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Faltam R\$ ${_fmt2(falta)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              )
            else if (_vendaFiada && totalPago > widget.total + 0.01)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Pagamento informado maior que o total da venda.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            else if (troco > 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.money, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Troco a dar: R\$ ${_fmt2(troco)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancelar,
          child: const Text('Voltar'),
        ),
        FilledButton.icon(
          onPressed: _valorOk ? _confirmar : null,
          icon: const Icon(Icons.check),
          label: const Text('Confirmar venda'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
          ),
        ),
      ],
    );
  }
}
