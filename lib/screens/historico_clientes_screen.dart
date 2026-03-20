// lib/screens/historico_clientes_screen.dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../utils/export_excel.dart';
import '../services/permissao_service.dart';
import '../services/reconciliacao_vendas_clientes_service.dart';
import '../services/migracao_vendas_itens_service.dart';
import '../services/deduplicacao_clientes_service.dart';
import '../services/clientes_firestore_service.dart';
import '../services/vendas_firestore_service.dart';
import '../services/sync_queue_service.dart';
import '../services/loja_id_service.dart';
import '../utils/text_utils.dart';
import 'historico_cliente_detalhe_screen.dart';

// Cores do tema (alinhado com vendas_screen)
const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _cardColor = Color(0xFFFFFFFF);
const Color _backgroundColor = Color(0xFFF8FAFC);
const Color _surfaceColor = Color(0xFF1E293B);

class HistoricoClientesScreen extends StatefulWidget {
  const HistoricoClientesScreen({super.key});

  @override
  State<HistoricoClientesScreen> createState() => _HistoricoClientesScreenState();
}

class _HistoricoClientesScreenState extends State<HistoricoClientesScreen> {
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;

  final TextEditingController _filtroController = TextEditingController();

  String? lojaId;
  bool _erroResolucaoLoja = false;

  DateTime? dataInicial;
  DateTime? dataFinal;
  String ordenacaoClientes = 'alfabetica'; // alfabetica | alfabetica_desc | data

  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _init();
    _filtroController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _filtroController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _verificarPermissao();
    if (!mounted) return;

    lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (lojaId == null || lojaId!.trim().isEmpty) {
      if (mounted) setState(() { _carregando = false; _erroResolucaoLoja = true; });
      return;
    }

    clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId!));
    vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId!));

    try {
      await SyncQueueService.processPending();
    } catch (e) {
      debugPrint('HistoricoClientesScreen _init SyncQueue: $e');
    }

    try {
      await ClientesFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        clientesBox: clientesBox,
      );
      await VendasFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        vendasBox: vendasBox,
      );
    } catch (e) {
      debugPrint('HistoricoClientesScreen _init sync Firestore: $e');
    }

    try {
      await ReconciliacaoVendasClientesService.reconciliar(
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        lojaId: lojaId!,
      );
      await MigracaoVendasItensService.migrarVendasDaBox(vendasBox);
      await DeduplicacaoClientesService.deduplicar(clientesBox, vendasBox, lojaId!);
    } catch (e) {
      debugPrint('HistoricoClientesScreen _init reconciliacao/deduplicacao: $e');
    }

    if (mounted) {
      setState(() => _carregando = false);
    }
  }

  Future<void> _verificarPermissao() async {
    final permitido = await PermissaoService.possuiPermissao('historico_cliente');
    if (!permitido && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para acessar esta tela'),
        ),
      );
    }
  }

  Future<void> _selecionarDataInicial() async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataInicial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (data != null) setState(() => dataInicial = data);
  }

  Future<void> _selecionarDataFinal() async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataFinal ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (data != null) setState(() => dataFinal = data);
  }

  void _aplicarPeriodoRapido(String periodo) {
    final agora = DateTime.now();
    final fim = DateTime(agora.year, agora.month, agora.day, 23, 59, 59);
    DateTime inicio;
    switch (periodo) {
      case 'hoje':
        inicio = DateTime(agora.year, agora.month, agora.day);
        break;
      case 'semana':
        final diff = agora.weekday - 1;
        inicio = DateTime(agora.year, agora.month, agora.day - diff);
        break;
      case 'mes':
        inicio = DateTime(agora.year, agora.month, 1);
        break;
      default:
        return;
    }
    setState(() {
      dataInicial = inicio;
      dataFinal = fim;
    });
  }

  // ==========================================================================================
  // 🔥 FONTE DE VERDADE: vendas vêm da vendasBox (não de cliente.historico)
  // ==========================================================================================
  List<Venda> _vendasFiltradas() {
    var di = dataInicial;
    var df = dataFinal;
    if (di != null && df != null && df.isBefore(di)) {
      di = dataFinal;
      df = dataInicial;
    }

    final todasVendas = vendasBox.values.where((v) {
      if (v.lojaId != null && v.lojaId!.isNotEmpty && v.lojaId != lojaId) {
        return false;
      }
      return true;
    }).toList();

    final filtro = _filtroController.text.trim();

    return todasVendas.where((venda) {
      final bool dentroDoIntervalo =
          (di == null ||
              venda.data.isAfter(di.subtract(const Duration(days: 1)))) &&
          (df == null ||
              venda.data.isBefore(df.add(const Duration(days: 1))));

      final bool contemNome = filtro.isEmpty ||
          normalizeText(venda.clienteNome).contains(normalizeText(filtro));

      return dentroDoIntervalo && contemNome;
    }).toList()
      ..sort((a, b) => b.data.compareTo(a.data));
  }

  Widget _buildChipPeriodo(String label, String periodo) {
    final hoje = DateTime.now();
    DateTime? inicioEsperado;
    switch (periodo) {
      case 'hoje':
        inicioEsperado = DateTime(hoje.year, hoje.month, hoje.day);
        break;
      case 'semana':
        final diff = hoje.weekday - 1;
        inicioEsperado = DateTime(hoje.year, hoje.month, hoje.day - diff);
        break;
      case 'mes':
        inicioEsperado = DateTime(hoje.year, hoje.month, 1);
        break;
    }
    final selecionado = dataInicial != null &&
        inicioEsperado != null &&
        dataInicial!.year == inicioEsperado.year &&
        dataInicial!.month == inicioEsperado.month &&
        dataInicial!.day == inicioEsperado.day;

    return FilterChip(
      label: Text(label),
      selected: selecionado,
      onSelected: (_) => _aplicarPeriodoRapido(periodo),
      selectedColor: _primaryColor.withValues(alpha:0.2),
      checkmarkColor: _primaryColor,
    );
  }

  /// Agrupa vendas por cliente (nome normalizado para evitar duplicatas na exibição)
  Map<String, List<Venda>> _vendasPorCliente(List<Venda> vendas) {
    final mapa = <String, List<Venda>>{};
    for (final v in vendas) {
      final chave = normalizeText(v.clienteNome);
      if (chave.isEmpty) continue;
      mapa.putIfAbsent(chave, () => []).add(v);
    }
    for (final lista in mapa.values) {
      lista.sort((a, b) => b.data.compareTo(a.data));
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        appBar: AppBar(title: const Text('Histórico de Clientes')),
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
                    setState(() { _erroResolucaoLoja = false; _carregando = true; });
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
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Histórico de Clientes'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final vendas = _vendasFiltradas();
    final porCliente = _vendasPorCliente(vendas);
    final clientesUnicos = porCliente.keys.toList();
    if (clientesUnicos.isNotEmpty && vendas.isNotEmpty) {
      if (ordenacaoClientes == 'data') {
        clientesUnicos.sort((a, b) {
          final vendasA = porCliente[a] ?? [];
          final vendasB = porCliente[b] ?? [];
          final dataA = vendasA.isNotEmpty ? vendasA.first.data : DateTime(2000);
          final dataB = vendasB.isNotEmpty ? vendasB.first.data : DateTime(2000);
          return dataB.compareTo(dataA); // mais recente primeiro
        });
      } else if (ordenacaoClientes == 'alfabetica_desc') {
        clientesUnicos.sort((a, b) {
          final nomeA = vendas.firstWhereOrNull(
                (v) => normalizeText(v.clienteNome) == a,
              )?.clienteNome ??
              a;
          final nomeB = vendas.firstWhereOrNull(
                (v) => normalizeText(v.clienteNome) == b,
              )?.clienteNome ??
              b;
          return nomeB.toLowerCase().compareTo(nomeA.toLowerCase()); // Z-A
        });
      } else {
        clientesUnicos.sort((a, b) {
          final nomeA = vendas.firstWhereOrNull(
                (v) => normalizeText(v.clienteNome) == a,
              )?.clienteNome ??
              a;
          final nomeB = vendas.firstWhereOrNull(
                (v) => normalizeText(v.clienteNome) == b,
              )?.clienteNome ??
              b;
          return nomeA.toLowerCase().compareTo(nomeB.toLowerCase()); // A-Z
        });
      }
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('Histórico de Clientes'),
        backgroundColor: _cardColor,
        foregroundColor: _surfaceColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Exportar para Excel',
            onPressed: vendas.isEmpty
                ? null
                : () => exportarParaExcelComDialog(context, vendas),
          ),
        ],
      ),
      body: Column(
        children: [
          // ====== FILTRO SUPERIOR (estilo vendas) ======
          Container(
            padding: const EdgeInsets.all(16),
            color: _cardColor,
            child: Column(
              children: [
                TextField(
                  controller: _filtroController,
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChipPeriodo('Hoje', 'hoje'),
                      const SizedBox(width: 8),
                      _buildChipPeriodo('Semana', 'semana'),
                      const SizedBox(width: 8),
                      _buildChipPeriodo('Mês', 'mes'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selecionarDataInicial,
                        icon: Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: dataInicial != null ? _primaryColor : Colors.grey,
                        ),
                        label: Text(
                          dataInicial == null
                              ? 'Data inicial'
                              : DateFormat('dd/MM/yy').format(dataInicial!),
                          style: TextStyle(
                            color: dataInicial != null ? _primaryColor : Colors.grey[600],
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: dataInicial != null ? _primaryColor : Colors.grey.shade300,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey[400]),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selecionarDataFinal,
                        icon: Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: dataFinal != null ? _primaryColor : Colors.grey,
                        ),
                        label: Text(
                          dataFinal == null
                              ? 'Data final'
                              : DateFormat('dd/MM/yy').format(dataFinal!),
                          style: TextStyle(
                            color: dataFinal != null ? _primaryColor : Colors.grey[600],
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: dataFinal != null ? _primaryColor : Colors.grey.shade300,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    if (dataInicial != null || dataFinal != null)
                      IconButton(
                        onPressed: () => setState(() {
                          dataInicial = null;
                          dataFinal = null;
                        }),
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'Limpar filtros',
                      ),
                  ],
                ),
                if (vendas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _successColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${vendas.length} venda(s) no período',
                          style: const TextStyle(
                            color: _successColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'R\$ ${vendas.fold<double>(0, (s, v) => s + v.total).toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: _successColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: ordenacaoClientes,
                      icon: const Icon(Icons.sort, color: _primaryColor, size: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      onChanged: (value) {
                        if (value != null) setState(() => ordenacaoClientes = value);
                      },
                      items: const [
                        DropdownMenuItem(value: 'alfabetica', child: Text('Ordenar: Alfabética (A-Z)')),
                        DropdownMenuItem(value: 'alfabetica_desc', child: Text('Ordenar: Alfabética (Z-A)')),
                        DropdownMenuItem(value: 'data', child: Text('Ordenar: Data (mais recente)')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ====== CLIENTES (agrupados, sem duplicatas) ======
          Expanded(
            child: RefreshIndicator(
              onRefresh: _init,
              child: clientesUnicos.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma venda encontrada',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dataInicial != null || dataFinal != null
                              ? 'Tente outro período ou ajuste os filtros'
                              : 'As vendas aparecerão aqui',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: clientesUnicos.length,
                    itemBuilder: (context, index) {
                      final chave = clientesUnicos[index];
                      final vendasCliente = porCliente[chave] ?? [];
                      final nomeCliente = vendasCliente.first.clienteNome;
                      final totalGasto = vendasCliente.fold<double>(
                        0, (s, v) => s + v.total,
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha:0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              final cliente = clientesBox.values.firstWhereOrNull(
                                (c) => normalizeText(c.nome) == chave,
                              );
                              final telefone = cliente?.telefone;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => HistoricoClienteDetalheScreen(
                                    clienteNome: nomeCliente,
                                    clienteTelefone: telefone,
                                    vendasBox: vendasBox,
                                    lojaId: lojaId!,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: _primaryColor.withValues(alpha:0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.person, size: 24, color: _primaryColor),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nomeCliente,
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                                color: _surfaceColor,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${vendasCliente.length} compra(s)',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _successColor.withValues(alpha:0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          'R\$ ${totalGasto.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: _successColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}



