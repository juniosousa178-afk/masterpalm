// lib/screens/notas_fiscais_screen.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/hive_box_names.dart';
import '../models/cliente.dart';
import '../models/nota_fiscal.dart';
import '../models/venda.dart';
import '../services/nota_fiscal_service.dart';
import '../services/nota_fiscal_firestore_service.dart';
import '../services/loja_id_service.dart';
import '../services/permissao_service.dart';
import '../services/via_cep_service.dart';
import '../widgets/app_help_icon_button.dart';

class NotasFiscaisScreen extends StatefulWidget {
  const NotasFiscaisScreen({super.key});

  @override
  State<NotasFiscaisScreen> createState() => _NotasFiscaisScreenState();
}

class _NotasFiscaisScreenState extends State<NotasFiscaisScreen>
    with SingleTickerProviderStateMixin {
  late Box<NotaFiscal> notasBox;
  late Box<Venda> vendasBox;

  String? lojaId;
  bool _carregando = true;
  bool _erroResolucaoLoja = false;
  String _filtroStatus = 'todas';
  final _buscaClienteController = TextEditingController();

  late TabController _tabController;

  // Controllers para configuração
  final _apiTokenController = TextEditingController();
  final _cepOrigemController = TextEditingController();
  String _providerSelecionado = 'focusnfe';
  bool _modoProducao = false;

  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1); // Indigo
  static const Color _successColor = Color(0xFF22C55E); // Green
  static const Color _warningColor = Color(0xFFF59E0B); // Amber
  static const Color _errorColor = Color(0xFFEF4444); // Red
  static const Color _cardColor = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _init();
  }

  Future<void> _init() async {
    await _verificarPermissao();

    lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (lojaId == null || lojaId!.trim().isEmpty) {
      if (mounted) setState(() { _carregando = false; _erroResolucaoLoja = true; });
      return;
    }

    notasBox = await Hive.openBox<NotaFiscal>(HiveBoxNames.notasFiscais(lojaId!));
    vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId!));

    // Sincronizar do Firestore
    try {
      await NotaFiscalFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        notasBox: notasBox,
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao sincronizar notas do Firestore (type=${e.runtimeType})');
    }

    // Carregar configurações salvas e aplicar no serviço (evita token “morto” até salvar de novo)
    await _carregarConfiguracoes();
    _aplicarConfigNoNotaFiscalService();

    if (mounted) {
      setState(() {
        _carregando = false;
      });
    }
  }

  /// Aplica token/ambiente da UI (ou Hive recém-carregado) em [NotaFiscalService].
  void _aplicarConfigNoNotaFiscalService() {
    NotaFiscalService.configure(
      apiToken: _apiTokenController.text.trim(),
      producao: _modoProducao,
    );
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      final configBox = await Hive.openBox(HiveBoxNames.notaFiscalConfig(lojaId!));
      _apiTokenController.text = configBox.get('apiToken', defaultValue: '');
      _cepOrigemController.text = configBox.get('cepOrigem', defaultValue: '');
      _providerSelecionado = configBox.get('provider', defaultValue: 'focusnfe');
      _modoProducao = configBox.get('producao', defaultValue: false);
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar configurações de NF-e (type=${e.runtimeType})');
    }
  }

  Future<void> _salvarConfiguracoes() async {
    try {
      final configBox = await Hive.openBox(HiveBoxNames.notaFiscalConfig(lojaId!));
      await configBox.put('apiToken', _apiTokenController.text.trim());
      await configBox.put('cepOrigem', _cepOrigemController.text.trim());
      await configBox.put('provider', _providerSelecionado);
      await configBox.put('producao', _modoProducao);

      _aplicarConfigNoNotaFiscalService();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Configurações salvas com sucesso!'),
              ],
            ),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar configurações: $e'),
            backgroundColor: _errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _verificarPermissao() async {
    final sessao = await Hive.openBox('sessao');
    final tipo = (sessao.get('tipo_usuario', defaultValue: 'vendedor') as String)
        .trim()
        .toLowerCase();
    // Admin e programador sempre têm acesso
    if (tipo == 'admin' || tipo == 'programador') return;
    final permitido = await PermissaoService.possuiPermissao('notas_fiscais');
    if (!permitido && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para acessar esta tela'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiTokenController.dispose();
    _cepOrigemController.dispose();
    _buscaClienteController.dispose();
    super.dispose();
  }

  /// Busca cliente cadastrado para pré-preencher dados (por clienteId ou nome)
  Future<Cliente?> _buscarClientePorVenda(Venda venda) async {
    try {
      final clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId!));
      final nomeNorm = venda.clienteNome.trim().toLowerCase();
      for (final c in clientesBox.values) {
        if (venda.clienteId != null &&
            venda.clienteId!.isNotEmpty &&
            c.idFirebase == venda.clienteId) {
          return c;
        }
        if (c.nome.trim().toLowerCase() == nomeNorm) return c;
      }
    } catch (_) {}
    return null;
  }

  List<NotaFiscal> _notasFiltradas() {
    var notas = notasBox.values.where((n) => n.lojaId == lojaId).toList();

    if (_filtroStatus != 'todas') {
      notas = notas
          .where((n) =>
              NotaFiscalService.normalizarStatusApiParaApp(n.status) ==
              _filtroStatus)
          .toList();
    }

    final busca = _buscaClienteController.text.trim().toLowerCase();
    if (busca.isNotEmpty) {
      notas = notas
          .where((n) =>
              n.clienteNome.toLowerCase().contains(busca) ||
              n.numero.contains(busca))
          .toList();
    }

    notas.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));
    return notas;
  }

  // Estatísticas
  Map<String, dynamic> _calcularEstatisticas() {
    final notas = notasBox.values.where((n) => n.lojaId == lojaId).toList();
    final emitidas = notas
        .where((n) =>
            NotaFiscalService.normalizarStatusApiParaApp(n.status) == 'emitida')
        .toList();
    final pendentes = notas
        .where((n) =>
            NotaFiscalService.normalizarStatusApiParaApp(n.status) == 'pendente')
        .toList();
    final valorTotal = emitidas.fold<double>(0, (sum, n) => sum + n.valorTotal);

    return {
      'total': notas.length,
      'emitidas': emitidas.length,
      'pendentes': pendentes.length,
      'valorTotal': valorTotal,
    };
  }

  Future<void> _abrirBottomSheetNovaNotaFiscal() async {
    // Listar vendas sem nota fiscal
    final vendasSemNota = vendasBox.values
        .where((v) => v.lojaId == lojaId)
        .where((v) {
          final jaTemNota = notasBox.values.any((n) => n.vendaId == v.idFirebase);
          return !jaTemNota;
        })
        .toList()
      ..sort((a, b) => b.data.compareTo(a.data));

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.receipt_long, color: _primaryColor),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selecionar Venda',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Escolha uma venda para emitir NF-e',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Lista
              Expanded(
                child: vendasSemNota.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 64,
                              color: _successColor.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Tudo em dia!',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Todas as vendas já possuem nota fiscal',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: vendasSemNota.length,
                        itemBuilder: (context, index) {
                          final venda = vendasSemNota[index];
                          return _buildVendaCard(venda);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVendaCard(Venda venda) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(context);
            _emitirNotaParaVenda(venda);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(venda.clienteNome),
                      style: const TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venda.clienteNome,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(venda.data),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'R\$ ${venda.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _successColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Emitir NF-e',
                        style: TextStyle(
                          color: _primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Future<void> _emitirNotaParaVenda(Venda venda) async {
    // Buscar cliente para pré-preenchimento
    final cliente = await _buscarClientePorVenda(venda);
    if (!mounted) return;

    final cpfCnpjController = TextEditingController();
    final enderecoController = TextEditingController(
      text: cliente?.endereco ?? '',
    );
    final cidadeController = TextEditingController(
      text: cliente?.cidade ?? '',
    );
    final estadoController = TextEditingController(
      text: 'SP',
    );
    final cepController = TextEditingController(
      text: cliente?.cep ?? '',
    );
    final observacoesController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person, color: _primaryColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dados do Cliente',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          venda.clienteNome,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Formulário
            Expanded(
              child: StatefulBuilder(
                builder: (context, setFormState) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildModernTextField(
                          controller: cpfCnpjController,
                          label: 'CPF/CNPJ',
                          hint: '000.000.000-00',
                          icon: Icons.badge,
                          required: true,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        _buildModernTextField(
                          controller: enderecoController,
                          label: 'Endereço',
                          hint: 'Rua, número, complemento',
                          icon: Icons.location_on,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildModernTextField(
                                controller: cidadeController,
                                label: 'Cidade',
                                hint: 'São Paulo',
                                icon: Icons.location_city,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildModernTextField(
                                controller: estadoController,
                                label: 'UF',
                                hint: 'SP',
                                icon: Icons.map,
                                maxLength: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildModernTextField(
                                controller: cepController,
                                label: 'CEP',
                                hint: '00000-000',
                                icon: Icons.markunread_mailbox,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final cep = cepController.text.trim();
                                  if (cep.length < 8) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Digite um CEP válido (8 dígitos)'),
                                        backgroundColor: _errorColor,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }
                                  final result = await ViaCepService.buscar(cep);
                                  if (result != null && context.mounted) {
                                    enderecoController.text = result.enderecoCompleto;
                                    cidadeController.text = result.localidade;
                                    estadoController.text = result.uf;
                                    cepController.text = result.cep;
                                    setFormState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Endereço encontrado: ${result.localidade}/${result.uf}'),
                                        backgroundColor: _successColor,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  } else if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('CEP não encontrado'),
                                        backgroundColor: _errorColor,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.search, size: 18),
                                label: const Text('Buscar'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildModernTextField(
                          controller: observacoesController,
                          label: 'Observações',
                          hint: 'Informações adicionais...',
                          icon: Icons.notes,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Botões
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (cpfCnpjController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('CPF/CNPJ é obrigatório'),
                              backgroundColor: _errorColor,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(context, true);
                      },
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Emitir NF-e'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    // Criar itens da nota a partir da venda
    final itens = (venda.itens ?? []).map((item) {
      return NotaFiscalItem(
        produtoNome: item.produtoNome,
        quantidade: item.quantidade,
        valorUnitario: item.precoUnitario,
        valorTotal: item.precoUnitario * item.quantidade,
        unidade: 'UN',
      );
    }).toList();

    // Gerar número da nota
    final numero = await NotaFiscalService.gerarProximoNumero(
      lojaId: lojaId!,
      serie: '1',
    );

    // Criar nota fiscal
    final nota = NotaFiscal.fromVenda(
      numero: numero,
      serie: '1',
      clienteNome: venda.clienteNome,
      clienteCpfCnpj: cpfCnpjController.text,
      clienteEndereco:
          enderecoController.text.isEmpty ? null : enderecoController.text,
      clienteCidade:
          cidadeController.text.isEmpty ? null : cidadeController.text,
      clienteEstado: estadoController.text.isEmpty
          ? null
          : estadoController.text.toUpperCase(),
      clienteCep: cepController.text.isEmpty ? null : cepController.text,
      valorTotal: venda.total,
      valorProdutos: venda.preco,
      valorFrete: venda.frete,
      valorDesconto: venda.descontoValor,
      itens: itens,
      lojaId: lojaId!,
      vendaId: venda.idFirebase,
      observacoes:
          observacoesController.text.isEmpty ? null : observacoesController.text,
    );

    await notasBox.add(nota);

    // Sincronizar com Firestore
    try {
      await NotaFiscalFirestoreService.syncNotaFiscal(nota, lojaId: lojaId!);
    } catch (e) {
      debugPrint('⚠️ Erro ao sincronizar nota (type=${e.runtimeType})');
    }

    if (!mounted) return;

    // Perguntar: salvar pendente ou emitir na SEFAZ agora
    final emitirAgora = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long, color: _primaryColor),
            ),
            const SizedBox(width: 12),
            const Text('Próximo passo'),
          ],
        ),
        content: const Text(
          'Nota fiscal criada com sucesso!\n\n'
          'Deseja enviar para a SEFAZ agora ou salvar como pendente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Salvar pendente'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Emitir na SEFAZ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (emitirAgora == true) {
      _emitirNotaFiscal(nota);
    } else {
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nota salva como pendente. Emita depois na aba Emitidas.'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    int? maxLength,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _primaryColor),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        counterText: '',
      ),
    );
  }

  Future<void> _cancelarNotaFiscal(NotaFiscal nota) async {
    if (nota.chaveAcesso == null || nota.chaveAcesso!.isEmpty) return;

    final justificativaController = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cancel, color: _errorColor),
            ),
            const SizedBox(width: 12),
            const Text('Cancelar NF-e'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O cancelamento de NF-e é irreversível. Informe a justificativa (mínimo 15 caracteres):',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: justificativaController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Ex: Erro no cadastro do cliente',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          ElevatedButton(
            onPressed: () {
              final j = justificativaController.text.trim();
              if (j.length < 15) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Justificativa deve ter no mínimo 15 caracteres'),
                    backgroundColor: _errorColor,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancelar NF-e'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _primaryColor),
              SizedBox(height: 16),
              Text('Cancelando NF-e...'),
            ],
          ),
        ),
      ),
    );

    try {
      await NotaFiscalService.cancelarNota(
        chaveAcesso: nota.chaveAcesso!,
        justificativa: justificativaController.text.trim(),
      );
      nota.status = 'cancelada';
      await nota.save();
      try {
        await NotaFiscalFirestoreService.syncNotaFiscal(nota, lojaId: lojaId!);
      } catch (_) {}
      if (!mounted) return;
      Navigator.pop(context);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NF-e cancelada com sucesso'),
          backgroundColor: _successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotaFiscalService.mensagemErroHumano(e)),
          backgroundColor: _errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _emitirNotaFiscal(NotaFiscal nota) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _primaryColor),
              SizedBox(height: 16),
              Text('Emitindo NF-e...'),
            ],
          ),
        ),
      ),
    );

    try {
      final resultado = await NotaFiscalService.emitirNotaFiscal(nota);

      if (!mounted) return;
      Navigator.pop(context); // Fechar loading

      try {
        await NotaFiscalFirestoreService.syncNotaFiscal(nota, lojaId: lojaId!);
      } catch (e) {
        debugPrint('⚠️ Sync Firestore pós-emissão (type=${e.runtimeType}): $e');
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_circle, color: _successColor),
              ),
              const SizedBox(width: 12),
              const Text('NF-e Emitida!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Chave', resultado['chaveAcesso'] ?? 'N/A'),
              _buildInfoRow('Protocolo', resultado['protocolo'] ?? 'N/A'),
              _buildInfoRow('Status', resultado['status'] ?? 'N/A'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
            if (resultado['pdfUrl'] != null)
              ElevatedButton.icon(
                onPressed: () {
                  launchUrl(Uri.parse(resultado['pdfUrl']));
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Ver DANFE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Fechar loading

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error, color: _errorColor),
              ),
              const SizedBox(width: 12),
              const Text('Erro ao Emitir'),
            ],
          ),
          content: Text(NotaFiscalService.mensagemErroHumano(e)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notas fiscais')),
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
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: _primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Notas Fiscais",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          AppHelpIconButton(iconColor: Colors.white),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: _primaryColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Emitidas', icon: Icon(Icons.receipt_long, size: 20)),
                Tab(text: 'Pendentes', icon: Icon(Icons.pending_actions, size: 20)),
                Tab(text: 'Config', icon: Icon(Icons.settings, size: 20)),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotasTab(),
          _buildVendasSemNotaTab(),
          _buildConfigTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirBottomSheetNovaNotaFiscal,
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nova NF-e'),
      ),
    );
  }

  Widget _buildNotasTab() {
    final stats = _calcularEstatisticas();

    return Column(
      children: [
        // Estatísticas
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.receipt,
                  label: 'Total',
                  value: stats['total'].toString(),
                  color: _primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.check_circle,
                  label: 'Emitidas',
                  value: stats['emitidas'].toString(),
                  color: _successColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.attach_money,
                  label: 'Valor',
                  value: 'R\$ ${NumberFormat('#,##0.00', 'pt_BR').format(stats['valorTotal'])}',
                  color: _warningColor,
                  isLarge: true,
                ),
              ),
            ],
          ),
        ),

        // Busca por cliente/número
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _buscaClienteController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por cliente ou número...',
              prefixIcon: const Icon(Icons.search, color: _primaryColor),
              suffixIcon: _buscaClienteController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _buscaClienteController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Filtros
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_list, color: _primaryColor),
                const SizedBox(width: 12),
                const Text('Status:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filtroStatus,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'todas', child: Text('Todas')),
                        DropdownMenuItem(value: 'pendente', child: Text('Pendentes')),
                        DropdownMenuItem(value: 'emitida', child: Text('Emitidas')),
                        DropdownMenuItem(value: 'cancelada', child: Text('Canceladas')),
                        DropdownMenuItem(value: 'erro', child: Text('Erro')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _filtroStatus = value ?? 'todas';
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Lista de notas
        Expanded(
          child: ValueListenableBuilder<Box<NotaFiscal>>(
            valueListenable: notasBox.listenable(),
            builder: (context, box, _) {
              final notas = _notasFiltradas();

              if (notas.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma nota fiscal encontrada',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: notas.length,
                itemBuilder: (context, index) {
                  final nota = notas[index];
                  return _buildNotaCard(nota);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isLarge = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isLarge ? 14 : 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotaCard(NotaFiscal nota) {
    final statusNorm =
        NotaFiscalService.normalizarStatusApiParaApp(nota.status);
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (statusNorm) {
      case 'emitida':
        statusColor = _successColor;
        statusIcon = Icons.check_circle;
        statusLabel = 'Emitida';
        break;
      case 'cancelada':
        statusColor = _errorColor;
        statusIcon = Icons.cancel;
        statusLabel = 'Cancelada';
        break;
      case 'erro':
        statusColor = _warningColor;
        statusIcon = Icons.error;
        statusLabel = 'Erro';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
        statusLabel = 'Pendente';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(statusIcon, color: statusColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'NF-e ${nota.numero}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nota.clienteNome,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'R\$ ${nota.valorTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(nota.dataEmissao),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (statusNorm == 'pendente')
                  TextButton.icon(
                    onPressed: () => _emitirNotaFiscal(nota),
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Emitir'),
                    style: TextButton.styleFrom(
                      foregroundColor: _primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                if (statusNorm == 'emitida' && nota.chaveAcesso != null)
                  TextButton.icon(
                    onPressed: () => _cancelarNotaFiscal(nota),
                    icon: const Icon(Icons.cancel, size: 16),
                    label: const Text('Cancelar'),
                    style: TextButton.styleFrom(
                      foregroundColor: _errorColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                if (nota.pdfUrl != null)
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(nota.pdfUrl!)),
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('DANFE'),
                    style: TextButton.styleFrom(
                      foregroundColor: _successColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendasSemNotaTab() {
    return ValueListenableBuilder<Box<Venda>>(
      valueListenable: vendasBox.listenable(),
      builder: (context, box, _) {
        final vendasSemNota = vendasBox.values
            .where((v) => v.lojaId == lojaId)
            .where((v) {
              final jaTemNota =
                  notasBox.values.any((n) => n.vendaId == v.idFirebase);
              return !jaTemNota;
            })
            .toList()
          ..sort((a, b) => b.data.compareTo(a.data));

        if (vendasSemNota.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _successColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 64,
                    color: _successColor,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Tudo em dia!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Todas as vendas possuem nota fiscal',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Header informativo
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warningColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: _warningColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${vendasSemNota.length} vendas aguardando emissão de NF-e',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Lista
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: vendasSemNota.length,
                itemBuilder: (context, index) {
                  final venda = vendasSemNota[index];
                  return _buildVendaPendenteCard(venda);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVendaPendenteCard(Venda venda) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _getInitials(venda.clienteNome),
                  style: const TextStyle(
                    color: _warningColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venda.clienteNome,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy').format(venda.data),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'R\$ ${venda.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _successColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _emitirNotaParaVenda(venda),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('Emitir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =================================================================
  // ABA DE CONFIGURAÇÕES
  // =================================================================
  Widget _buildConfigTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card de informação
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryColor,
                  _primaryColor.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.settings, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuração de NF-e',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Configure seu provedor para emitir notas fiscais',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Seleção de provedor
          _buildSectionTitle('1. Escolha o Provedor'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: DropdownButtonFormField<String>(
              value: _providerSelecionado,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.business, color: _primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'focusnfe',
                  child: Text('Focus NFe (Recomendado)'),
                ),
                DropdownMenuItem(value: 'sebrae', child: Text('Sebrae NFe')),
                DropdownMenuItem(value: 'webmania', child: Text('WebMania')),
              ],
              onChanged: (value) {
                setState(() {
                  _providerSelecionado = value!;
                });
              },
            ),
          ),

          const SizedBox(height: 16),

          // Guia passo a passo
          if (_providerSelecionado == 'focusnfe') _buildGuiaFocusNFe(),
          if (_providerSelecionado == 'sebrae') _buildGuiaSebrae(),
          if (_providerSelecionado == 'webmania') _buildGuiaWebMania(),

          const SizedBox(height: 24),

          // Token da API
          _buildSectionTitle('2. Token da API'),
          const SizedBox(height: 12),
          _buildModernTextField(
            controller: _apiTokenController,
            label: 'Token da API',
            hint: 'Cole aqui o token fornecido pelo provedor',
            icon: Icons.vpn_key,
            required: true,
          ),

          const SizedBox(height: 24),

          // CEP de origem
          _buildSectionTitle('3. CEP de Origem'),
          const SizedBox(height: 12),
          _buildModernTextField(
            controller: _cepOrigemController,
            label: 'CEP de Origem',
            hint: 'Ex: 01310-100',
            icon: Icons.location_on,
            required: true,
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 24),

          // Modo de operação
          _buildSectionTitle('4. Modo de Operação'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: SwitchListTile(
              title: const Text(
                'Modo Produção',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _modoProducao
                    ? 'NFe será emitida oficialmente na SEFAZ'
                    : 'NFe será emitida em HOMOLOGAÇÃO (teste)',
                style: TextStyle(
                  color: _modoProducao ? _successColor : _warningColor,
                ),
              ),
              value: _modoProducao,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onChanged: (value) {
                setState(() {
                  _modoProducao = value;
                });
              },
            ),
          ),

          const SizedBox(height: 32),

          // Botão salvar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _salvarConfiguracoes,
              icon: const Icon(Icons.save),
              label: const Text('Salvar Configurações'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Links úteis
          _buildLinksUteis(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: _primaryColor,
      ),
    );
  }

  Widget _buildGuiaFocusNFe() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _successColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _successColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, color: _successColor),
              SizedBox(width: 8),
              Text(
                'Como Configurar Focus NFe',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPassoGuia('1', 'Acesse focusnfe.com.br e clique em "Cadastre-se"'),
          _buildPassoGuia('2', 'Escolha o plano (tem gratuito com 5 NFe/mês)'),
          _buildPassoGuia('3', 'Confirme seu email e faça login'),
          _buildPassoGuia('4', 'Vá em "Configurações" → "API"'),
          _buildPassoGuia('5', 'Clique em "Gerar Token" ou copie o existente'),
          _buildPassoGuia('6', 'Cole o token no campo acima'),
        ],
      ),
    );
  }

  Widget _buildGuiaSebrae() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Como Configurar Sebrae NFe',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPassoGuia('1', 'Procure o Sebrae da sua região'),
          _buildPassoGuia('2', 'Verifique se você se enquadra (MEI, ME, EPP)'),
          _buildPassoGuia('3', 'Agende um atendimento'),
          _buildPassoGuia('4', 'Leve seus documentos'),
          _buildPassoGuia('5', 'Solicite as credenciais de API'),
        ],
      ),
    );
  }

  Widget _buildGuiaWebMania() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, color: Colors.purple),
              SizedBox(width: 8),
              Text(
                'Como Configurar WebMania',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPassoGuia('1', 'Acesse webmaniabr.com e cadastre-se'),
          _buildPassoGuia('2', 'Escolha o plano de NF-e'),
          _buildPassoGuia('3', 'Vá em "Chaves de Aplicação"'),
          _buildPassoGuia('4', 'Copie Consumer Key e Secret'),
          _buildPassoGuia('5', 'Cole no formato key:secret'),
        ],
      ),
    );
  }

  Widget _buildPassoGuia(String numero, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: _primaryColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                numero,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinksUteis() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.link, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Links Úteis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLinkItem('Focus NFe', 'focusnfe.com.br', 'https://focusnfe.com.br'),
          _buildLinkItem('Sebrae', 'sebrae.com.br', 'https://www.sebrae.com.br'),
          _buildLinkItem('WebMania', 'webmaniabr.com', 'https://webmaniabr.com'),
        ],
      ),
    );
  }

  Widget _buildLinkItem(String titulo, String descricao, String url) {
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.open_in_new, size: 18, color: _primaryColor),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  descricao,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

