// Detalhar produtos de compra revenda_detalhar_depois (estoque sem novo financeiro).

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../core/hive_box_names.dart';
import '../../models/compra_fornecedor.dart';
import '../../models/compra_fornecedor_constants.dart';
import '../../models/produto.dart';
import '../../services/compra_fornecedor_hive_store.dart';
import '../../services/compra_revenda_detalhamento_service.dart';
import '../../utils/moeda_input_formatter.dart';
import '../../widgets/moeda_text_field.dart';
import '../produto_form_screen.dart';

class CompraDetalharProdutosScreen extends StatefulWidget {
  const CompraDetalharProdutosScreen({
    super.key,
    required this.lojaId,
    required this.compraId,
  });

  final String lojaId;
  final String compraId;

  @override
  State<CompraDetalharProdutosScreen> createState() =>
      _CompraDetalharProdutosScreenState();
}

class _CompraDetalharProdutosScreenState extends State<CompraDetalharProdutosScreen> {
  static const Color _primary = Color(0xFF6366F1);

  CompraFornecedor? _compra;
  bool _loading = true;
  bool _salvando = false;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final box = await CompraFornecedorHiveStore.openBox(widget.lojaId);
    _compra = box?.get(widget.compraId.trim());
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _dialogEntradaExistente(Produto p) async {
    final qtdCtrl = TextEditingController(text: '1');
    final custoCtrl = TextEditingController(
      text: MoedaInputFormatter.format(p.custoReal > 0 ? p.custoReal : 0),
    );
    final tamCtrl = TextEditingController();
    final corCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Entrada — ${p.nome}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              MoedaTextField(
                controller: custoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Custo unitário desta compra',
                  border: OutlineInputBorder(),
                ),
              ),
              if (p.usaVariacoes || p.estoquePorTamanho.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: tamCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tamanho (se aplicável)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: corCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cor (se aplicável)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
            child: const Text('Confirmar entrada'),
          ),
        ],
      ),
    );
    if (ok != true || _compra == null) return;

    final qtd = int.tryParse(qtdCtrl.text.trim()) ?? 0;
    final custo = MoedaInputFormatter.parse(custoCtrl.text);
    setState(() => _salvando = true);
    final r = await CompraRevendaDetalhamentoService.vincularProdutoExistente(
      lojaId: widget.lojaId,
      compra: _compra!,
      produto: p,
      quantidade: qtd,
      custoUnitario: custo,
      tamanho: tamCtrl.text.trim(),
      cor: corCtrl.text.trim(),
    );
    setState(() => _salvando = false);
    if (!mounted) return;
    if (r.sucesso && r.compraAtualizada != null) {
      setState(() => _compra = r.compraAtualizada);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto vinculado e estoque atualizado.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.mensagem.isEmpty ? 'Falha ao vincular.' : r.mensagem)),
      );
    }
  }

  Future<void> _selecionarProdutoExistente() async {
    final name = HiveBoxNames.produtos(widget.lojaId);
    final box = Hive.isBoxOpen(name)
        ? Hive.box<Produto>(name)
        : await Hive.openBox<Produto>(name);
    final produtos = box.values
        .where((p) => p.lojaId.isEmpty || p.lojaId == widget.lojaId)
        .toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    if (!mounted) return;
    final escolhido = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setM) {
            final filtrados = produtos
                .where((p) =>
                    q.isEmpty || p.nome.toLowerCase().contains(q.toLowerCase()))
                .take(150)
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar produto',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setM(() => q = v.trim().toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (_, i) {
                        final p = filtrados[i];
                        return ListTile(
                          title: Text(p.nome),
                          subtitle: Text(
                            'Est: ${p.quantidade} · Custo ${_moeda.format(p.custoReal)}',
                          ),
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
    if (escolhido != null) await _dialogEntradaExistente(escolhido);
  }

  Future<void> _cadastrarProdutoNovo() async {
    final salvo = await Navigator.push<Produto>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProdutoFormScreen(returnProductOnSave: true),
      ),
    );
    if (salvo == null || _compra == null) return;
    setState(() => _salvando = true);
    final r = await CompraRevendaDetalhamentoService.vincularProdutoNovoJaSalvo(
      lojaId: widget.lojaId,
      compra: _compra!,
      produto: salvo,
    );
    setState(() => _salvando = false);
    if (!mounted) return;
    if (r.sucesso && r.compraAtualizada != null) {
      setState(() => _compra = r.compraAtualizada);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto novo vinculado à compra.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.mensagem.isEmpty ? 'Falha ao vincular.' : r.mensagem)),
      );
    }
  }

  Future<void> _marcarConferido() async {
    if (_compra == null) return;
    setState(() => _salvando = true);
    final r = await CompraRevendaDetalhamentoService.marcarConferido(
      lojaId: widget.lojaId,
      compra: _compra!,
    );
    setState(() => _salvando = false);
    if (!mounted) return;
    if (r.sucesso && r.compraAtualizada != null) {
      setState(() => _compra = r.compraAtualizada);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compra marcada como conferida.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _compra;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhar produtos da compra'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      body: _loading || c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.fornecedorNome,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text('Data ${_fmt.format(c.dataCompra)}'),
                        const SizedBox(height: 8),
                        Text(
                          'Este processo movimenta estoque, mas não cria novo '
                          'financeiro nem novas Contas a Pagar.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const Divider(),
                        Text('Total da compra: ${_moeda.format(c.valorTotalFinanceiro)}'),
                        Text(
                          'Produtos detalhados: ${_moeda.format(c.valorProdutosDetalhados)}',
                        ),
                        Text(
                          'Diferença: ${_moeda.format(c.diferencaDetalhamento)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: c.diferencaDetalhamento.abs() > 0.05
                                ? Colors.orange.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                        Text(
                          'Status: ${CompraFornecedorStatusDetalhamento.legivel(c.statusDetalhamentoProdutos)}',
                        ),
                      ],
                    ),
                  ),
                ),
                if (c.diferencaDetalhamento.abs() > 0.05)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MaterialBanner(
                      content: const Text(
                        'Existe diferença entre o valor da compra e os produtos '
                        'detalhados. Você pode ajustar ou marcar como conferido.',
                      ),
                      leading: const Icon(Icons.warning_amber_outlined),
                      actions: [
                        TextButton(
                          onPressed: () {},
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'Itens vinculados',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (c.itensOuVazio.isEmpty)
                  const Text('Nenhum produto vinculado ainda.')
                else
                  ...c.itensOuVazio.map(
                    (it) => ListTile(
                      dense: true,
                      title: Text(it.produtoNome),
                      subtitle: Text(
                        '${it.quantidade} × ${_moeda.format(it.custoUnitario)} = '
                        '${_moeda.format(it.subtotal)}',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _salvando ? null : _selecionarProdutoExistente,
                  icon: const Icon(Icons.search),
                  label: const Text('Selecionar produto existente'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _salvando ? null : _cadastrarProdutoNovo,
                  icon: const Icon(Icons.add),
                  label: const Text('Cadastrar novo produto'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _salvando ? null : _marcarConferido,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Marcar como conferido'),
                ),
              ],
            ),
    );
  }
}
