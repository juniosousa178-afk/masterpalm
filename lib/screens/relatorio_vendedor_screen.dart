import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/venda.dart';
import '../services/loja_id_service.dart';
import '../services/permissao_service.dart';

class RelatorioVendedorScreen extends StatefulWidget {
  const RelatorioVendedorScreen({super.key});

  @override
  State<RelatorioVendedorScreen> createState() =>
      _RelatorioVendedorScreenState();
}

class _RelatorioVendedorScreenState extends State<RelatorioVendedorScreen> {
  String? vendedorSelecionado;
  late String lojaId;
  late Box<Venda> vendasBox;

  @override
  void initState() {
    super.initState();
    _initLoja();
    _verificarPermissao();
  }

  Future<void> _initLoja() async {
    final id = (await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10)))?.trim();
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => lojaId = '');
      return;
    }
    lojaId = id;

    // 🔥 abre somente as vendas da loja correta
    final nomeBox = HiveBoxNames.vendas(lojaId);
    if (Hive.isBoxOpen(nomeBox)) {
      vendasBox = Hive.box<Venda>(nomeBox);
    } else {
      vendasBox = await Hive.openBox<Venda>(nomeBox);
    }

    if (mounted) setState(() {});
  }

  Future<void> _verificarPermissao() async {
    final permitido =
        await PermissaoService.possuiPermissao('relatorios_vendedor');

    if (!permitido && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Você não tem permissão para acessar o relatório do vendedor.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (lojaId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF101010),
        appBar: AppBar(title: const Text('Relatório por Vendedor'), backgroundColor: const Color(0xFF1A1A1A)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('Nenhuma loja ativa. Faça login e selecione uma loja.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 24),
                ElevatedButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back), label: const Text('Voltar')),
              ],
            ),
          ),
        ),
      );
    }
    if (!Hive.isBoxOpen(HiveBoxNames.vendas(lojaId))) {
      return const Scaffold(
        backgroundColor: Color(0xFF101010),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final todosVendedores =
        vendasBox.values.map((v) => v.vendedor).toSet().toList();

    final vendasFiltradas = vendedorSelecionado == null
        ? vendasBox.values.toList()
        : vendasBox.values
            .where((v) => v.vendedor == vendedorSelecionado)
            .toList();

    final total = vendasFiltradas.fold<double>(
        0, (soma, v) => soma + (v.total));

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        title: const Text('Relatório por Vendedor'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Column(
        children: [
          // SELEÇÃO DE VENDEDOR
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              initialValue: vendedorSelecionado,
              hint: const Text(
                'Selecione um vendedor',
                style: TextStyle(color: Colors.white),
              ),
              dropdownColor: const Color(0xFF1A1A1A),
              decoration: const InputDecoration(
                labelText: 'Vendedor',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
              ),
              items: todosVendedores.map((v) {
                return DropdownMenuItem(
                  value: v,
                  child: Text(v, style: const TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => vendedorSelecionado = value);
              },
            ),
          ),

          // TOTAL DO VENDEDOR
          Text(
            'Total: R\$ ${total.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 10),

          // LISTA DE VENDAS
          Expanded(
            child: ListView.builder(
              itemCount: vendasFiltradas.length,
              itemBuilder: (_, index) {
                final venda = vendasFiltradas[index];
                return ListTile(
                  title: Text(
                    venda.produtosDescricao,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${venda.clienteNome} - ${venda.quantidade}x R\$${venda.preco.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: Text(
                    'R\$ ${venda.total.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}