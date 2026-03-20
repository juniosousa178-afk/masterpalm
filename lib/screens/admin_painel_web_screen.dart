// lib/screens/admin_painel_web.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/loja_id_service.dart';
import 'consolidate_stores_screen.dart';

class AdminPainelWeb extends StatefulWidget {
  const AdminPainelWeb({super.key});

  @override
  State<AdminPainelWeb> createState() => _AdminPainelWebState();
}

class _AdminPainelWebState extends State<AdminPainelWeb> {
  List<Map<String, dynamic>> vendas = [];
  bool carregando = true;
  String? _lojaId;

  // Filtros
  final TextEditingController clienteController = TextEditingController();
  final TextEditingController formaPagamentoController =
      TextEditingController();
  DateTime? dataInicio;
  DateTime? dataFim;

  @override
  void initState() {
    super.initState();
    _initLojaId();
  }

  Future<void> _initLojaId() async {
    _lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (_lojaId == null || _lojaId!.trim().isEmpty) {
      if (mounted) {
        setState(() {
          carregando = false;
          vendas = [];
        });
      }
      return;
    }
    await _carregarVendas();
  }

  Future<void> _carregarVendas() async {
    if (_lojaId == null || _lojaId!.trim().isEmpty) return;
    // ✅ Buscar apenas vendas da loja atual
    final snapshot = await FirebaseFirestore.instance
        .collection('lojas')
        .doc(_lojaId!)
        .collection('estoque_vendas')
        .get();

    final dados = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'cliente': data['clienteNome'] ?? data['cliente'] ?? '',
        'total': (data['total'] as num?)?.toDouble() ?? 0.0,
        'formaPagamento': data['formasPagamento'] ?? data['formaPagamento'] ?? '',
        'data': (data['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      };
    }).toList();

    setState(() {
      vendas = dados;
      carregando = false;
    });
  }

  void _aplicarFiltros() async {
    if (_lojaId == null || _lojaId!.trim().isEmpty) return;
    setState(() => carregando = true);

    // ✅ Buscar apenas vendas da loja atual
    final snapshot = await FirebaseFirestore.instance
        .collection('lojas')
        .doc(_lojaId!)
        .collection('estoque_vendas')
        .get();

    final dadosFiltrados = snapshot.docs.map((doc) {
      final data = doc.data();
      final dataVenda = (data['data'] as Timestamp?)?.toDate() ?? DateTime.now();

      return {
        'cliente': data['clienteNome'] ?? data['cliente'] ?? '',
        'total': (data['total'] as num?)?.toDouble() ?? 0.0,
        'formaPagamento': data['formasPagamento'] ?? data['formaPagamento'] ?? '',
        'data': dataVenda,
      };
    }).where((venda) {
      final clienteFiltro = clienteController.text.toLowerCase();
      final pagamentoFiltro = formaPagamentoController.text.toLowerCase();

      final dentroData = (dataInicio == null ||
              venda['data']
                  .isAfter(dataInicio!.subtract(const Duration(days: 1)))) &&
          (dataFim == null ||
              venda['data'].isBefore(dataFim!.add(const Duration(days: 1))));

      final clienteOk = clienteFiltro.isEmpty ||
          (venda['cliente']?.toString() ?? '').toLowerCase().contains(clienteFiltro);
      final pagamentoOk = pagamentoFiltro.isEmpty ||
          (venda['formaPagamento']?.toString() ?? '').toLowerCase().contains(pagamentoFiltro);

      return clienteOk && pagamentoOk && dentroData;
    }).toList();

    setState(() {
      vendas = dadosFiltrados;
      carregando = false;
    });
  }

  Widget _filtros() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Filtros:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: clienteController,
                decoration: const InputDecoration(labelText: 'Cliente'),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                controller: formaPagamentoController,
                decoration:
                    const InputDecoration(labelText: 'Forma de Pagamento'),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextButton(
                onPressed: () async {
                  final data = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.now().subtract(const Duration(days: 30)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (data != null) setState(() => dataInicio = data);
                },
                child: Text(dataInicio == null
                    ? 'Data Início'
                    : DateFormat('dd/MM/yyyy').format(dataInicio!)),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextButton(
                onPressed: () async {
                  final data = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (data != null) setState(() => dataFim = data);
                },
                child: Text(dataFim == null
                    ? 'Data Fim'
                    : DateFormat('dd/MM/yyyy').format(dataFim!)),
              ),
            ),
            ElevatedButton(
              onPressed: _aplicarFiltros,
              child: const Text('Aplicar Filtros'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tabelaResultados() {
    if (carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (vendas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('Nenhuma venda encontrada com os filtros selecionados.'),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Cliente')),
          DataColumn(label: Text('Data')),
          DataColumn(label: Text('Forma de Pagamento')),
          DataColumn(label: Text('Valor Total')),
        ],
        rows: vendas.map((venda) {
          return DataRow(cells: [
            DataCell(Text(venda['cliente'] ?? '')),
            DataCell(Text(DateFormat('dd/MM/yyyy').format(venda['data']))),
            DataCell(Text(venda['formaPagamento'])),
            DataCell(Text('R\$ ${venda['total'].toStringAsFixed(2)}')),
          ]);
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Admin Web'),
        actions: [
          // ✅ BOTÃO PARA CONSOLIDAR LOJAS
          IconButton(
            icon: const Icon(Icons.merge_type),
            tooltip: 'Consolidar Lojas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ConsolidateStoresScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Relatório de Vendas',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _filtros(),
            const SizedBox(height: 24),
            _tabelaResultados(),
          ],
        ),
      ),
    );
  }
}
