// lib/screens/pre_pedidos_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/combo_configuravel_resumo.dart';
import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../core/pre_pedido_sale_intent.dart';
import '../core/produto_variacao_extra.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/pre_pedido_service.dart';
import '../services/shipping_preorder_service.dart';
import '../services/catalog_cart_item_snapshot.dart';
import '../services/catalogo_pedido_historico_service.dart';
import '../services/catalogo_venda_side_effects_secundarios_service.dart';
import '../services/pos_pagamento_service.dart';
import '../services/vendas_service.dart';
import '../utils/cleanup_cancelled_orders.dart';
import '../utils/limpar_firestore.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';
import 'pre_pedidos/pre_pedido_operacional.dart';
import '../widgets/app_help_icon_button.dart';

/// Tela unificada para gerenciar pedidos (pré-pedidos do catálogo web)
/// ✅ APENAS ADMIN/PROGRAMADOR pode acessar (vendedor NUNCA)
class PrePedidosScreen extends StatefulWidget {
  final String lojaId;
  /// Se definido, ao carregar a lista o pedido é destacado (ex.: ao abrir por "Ver pedido" na notificação)
  final String? initialPedidoId;

  const PrePedidosScreen({
    super.key,
    required this.lojaId,
    this.initialPedidoId,
  });

  @override
  State<PrePedidosScreen> createState() => _PrePedidosScreenState();
}

class _PrePedidosScreenState extends State<PrePedidosScreen>
    with TickerProviderStateMixin {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _secondaryColor = Color(0xFF8B5CF6);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _surfaceColor = Color(0xFFF8FAFC);

  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final TextEditingController _searchController = TextEditingController();
  String _ordenacao = 'recente'; // recente | antigo | valor_maior | valor_menor
  bool _isOffline = false;
  bool _initialPedidoHighlightShown = false;
  bool _confirmandoPedido = false;

  @override
  void initState() {
    super.initState();

    // ✅ VERIFICAR ROLE: Vendedor NUNCA pode acessar pré-pedidos
    _verificarAcesso();

    _tabController = TabController(length: 2, vsync: this);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(() => _isOffline =
            result.length == 1 && result.first == ConnectivityResult.none);
      }
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _verificarConectividade());
    // Abrir na aba Pendentes quando veio de "Ver pedido" na notificação
    if (widget.initialPedidoId != null && widget.initialPedidoId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController.index != 0) {
          _tabController.animateTo(0);
        }
      });
    }
  }

  Future<void> _verificarConectividade() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _isOffline =
          result.length == 1 && result.first == ConnectivityResult.none);
    }
  }

  /// ✅ Verifica se usuário pode acessar (apenas admin/programador)
  Future<void> _verificarAcesso() async {
    try {
      final sessao = await Hive.openBox('sessao');
      final tipo =
          (sessao.get('tipo_usuario') ?? 'vendedor').toString().toLowerCase();

      // Vendedor NUNCA pode acessar pré-pedidos
      if (tipo == 'vendedor') {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Acesso negado. Apenas administradores podem gerenciar pré-pedidos.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      logW('⚠️ [PRE-PEDIDOS] Erro ao verificar acesso (type=${e.runtimeType})');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  String _formatarDataRelativa(dynamic dataCriacao) {
    if (dataCriacao == null) return 'Data não disponível';
    try {
      final timestamp = dataCriacao as dynamic;
      final dt = timestamp.toDate() as DateTime;
      final agora = DateTime.now();
      final diff = agora.difference(dt);
      if (diff.inMinutes < 1) return 'Agora';
      if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Há ${diff.inHours}h';
      if (diff.inDays < 7) return 'Há ${diff.inDays} dia(s)';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Data não disponível';
    }
  }

  bool _isPagamentoGateway(String pagamento) {
    final p = pagamento.toLowerCase();
    return p.contains('mercadopago') ||
        p.contains('mercado pago') ||
        p.contains('gateway') ||
        p.contains('cartão') ||
        p.contains('cartao') ||
        p == 'pix'; // PIX via gateway
  }

  Future<void> _abrirWhatsApp(String? telefone, String clienteNome) async {
    if (telefone == null || telefone.trim().isEmpty) {
      _showModernSnackBar('Telefone não informado', isWarning: true);
      return;
    }
    final numero = telefone.replaceAll(RegExp(r'[^\d]'), '');
    if (numero.length < 10) {
      _showModernSnackBar('Número inválido', isWarning: true);
      return;
    }
    final wa = numero.startsWith('55') ? numero : '55$numero';
    final uri = Uri.parse(
      'https://wa.me/$wa?text=${Uri.encodeComponent('Olá $clienteNome! Segue o retorno sobre seu pedido.')}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showModernSnackBar('Não foi possível abrir o WhatsApp', isError: true);
      }
    } catch (e, st) {
      logE('Erro ao abrir WhatsApp (type=${e.runtimeType})', error: e, st: st);
      _showModernSnackBar('Erro ao abrir WhatsApp', isError: true);
    }
  }

  void _showModernSnackBar(String message,
      {bool isError = false, bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline
                  : isWarning
                      ? Icons.warning_amber
                      : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError
            ? _errorColor
            : isWarning
                ? _warningColor
                : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _abrirSugestoesIaPedidos() {
    const resumo = 'Contexto: Tela de Pedidos (pré-pedidos do catálogo web). '
        'O lojista gerencia pedidos pendentes, confirmados e cancelados. '
        'Fluxo: cliente faz pedido pelo catálogo → pedido aparece como pendente → lojista confirma → entrega. '
        'Pergunte sobre: entregas, atrasos, organização de pendências, comunicação com cliente.';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => const _SugestoesIaPedidosScreen(resumoInicial: resumo),
      ),
    );
  }

  Future<void> _limparTodosPedidos() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  size: 48, color: _errorColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'LIMPAR TODOS OS PEDIDOS',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _errorColor.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  _buildWarningItem('Todos os pré-pedidos'),
                  _buildWarningItem('Todas as vendas'),
                  _buildWarningItem('Todos os pedidos do catálogo'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Esta ação NÃO PODE ser desfeita!\nProdutos e clientes serão mantidos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('LIMPAR TUDO'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    try {
      if (!mounted) return;
      showDialog(
        context: navigator.context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Limpando dados...'),
              ],
            ),
          ),
        ),
      );

      await limparApenasVendas(widget.lojaId);

      if (mounted) navigator.pop();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Todos os pedidos e vendas foram removidos!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) navigator.pop();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Erro ao limpar: $e'),
            backgroundColor: _errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.remove_circle, size: 16, color: _errorColor),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: Colors.grey[800])),
        ],
      ),
    );
  }

  Future<void> _limparPedidosCancelados() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _warningColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_sweep, size: 48, color: _warningColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Limpar Pedidos Cancelados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Esta ação irá remover permanentemente todos os pedidos cancelados antigos do banco de dados.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _warningColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirmar'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    try {
      if (!mounted) return;
      showDialog(
        context: navigator.context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Limpando pedidos...'),
              ],
            ),
          ),
        ),
      );

      await cleanupCancelledOrders(widget.lojaId);

      if (mounted) navigator.pop();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Pedidos cancelados removidos com sucesso!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) navigator.pop();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Erro ao limpar pedidos: $e'),
            backgroundColor: _errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PrePedidoService.streamPrePedidos(
          lojaId: widget.lojaId, status: 'todos'),
      builder: (context, countSnapshot) {
        final allPedidos = countSnapshot.data ?? [];
        final operacionalStats =
            PrePedidoOperacionalStats.fromLista(allPedidos);
        // Badge “Pendentes”: só fila ativa (pendente recente, não substituído, não “abandonado” heurístico)
        final pendenteCount = operacionalStats.filaAtiva;
        final todosCount = operacionalStats.total;

        // Destacar pedido ao abrir por "Ver pedido" na notificação
        if (widget.initialPedidoId != null &&
            !_initialPedidoHighlightShown &&
            allPedidos.isNotEmpty) {
          final found = allPedidos.any((p) => (p['id'] ?? '').toString() == widget.initialPedidoId);
          if (found) {
            _initialPedidoHighlightShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                // ignore: prefer_const_constructors
                SnackBar(
                  content: const Text('Pedido da notificação está na lista abaixo.'),
                  backgroundColor: _successColor,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            });
          }
        }

        return Scaffold(
          backgroundColor: _surfaceColor,
          body: FadeTransition(
            opacity: _fadeAnimation,
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                if (_isOffline)
                  const SliverToBoxAdapter(
                    child: _PrePedidosOfflineBanner(warningColor: _warningColor),
                  ),
                SliverAppBar(
                  expandedHeight: 140,
                  floating: false,
                  pinned: true,
                  backgroundColor: _primaryColor,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    const AppHelpIconButton(iconColor: Colors.white),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 22),
                      ),
                      tooltip: 'Sugestões com IA (entregas, pendências)',
                      onPressed: _abrirSugestoesIaPedidos,
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onSelected: (value) {
                        if (value == 'limpar_cancelados') {
                          _limparPedidosCancelados();
                        } else if (value == 'limpar_tudo') {
                          _limparTodosPedidos();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'limpar_cancelados',
                          child: Row(
                            children: [
                              Icon(Icons.delete_sweep,
                                  size: 20, color: _warningColor),
                              SizedBox(width: 12),
                              Text('Limpar cancelados'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'limpar_tudo',
                          child: Row(
                            children: [
                              Icon(Icons.delete_forever,
                                  size: 20, color: _errorColor),
                              SizedBox(width: 12),
                              Text('Limpar TUDO',
                                  style: TextStyle(
                                      color: _errorColor,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_primaryColor, _secondaryColor],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -50,
                            top: -50,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                          ),
                          Positioned(
                            left: -30,
                            bottom: -30,
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 20,
                            right: 20,
                            bottom: 60,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pedidos',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pré-pedidos do catálogo web',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: Colors.white,
                        indicatorWeight: 3,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white70,
                        labelStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.pending_actions, size: 18),
                                const SizedBox(width: 8),
                                const Text('Pendentes'),
                                if (pendenteCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$pendenteCount',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.list_alt, size: 18),
                                const SizedBox(width: 8),
                                const Text('Todos'),
                                if (todosCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$todosCount',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText:
                            'Buscar por cliente, telefone ou ID do pedido...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
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
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('Ordenar:',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Mais recente'),
                          selected: _ordenacao == 'recente',
                          onSelected: (_) =>
                              setState(() => _ordenacao = 'recente'),
                          selectedColor: _primaryColor.withOpacity(0.3),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Mais antigo'),
                          selected: _ordenacao == 'antigo',
                          onSelected: (_) =>
                              setState(() => _ordenacao = 'antigo'),
                          selectedColor: _primaryColor.withOpacity(0.3),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Maior valor'),
                          selected: _ordenacao == 'valor_maior',
                          onSelected: (_) =>
                              setState(() => _ordenacao = 'valor_maior'),
                          selectedColor: _primaryColor.withOpacity(0.3),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Menor valor'),
                          selected: _ordenacao == 'valor_menor',
                          onSelected: (_) =>
                              setState(() => _ordenacao = 'valor_menor'),
                          selectedColor: _primaryColor.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Fila ativa: ${operacionalStats.filaAtiva} · '
                      'Abandono potencial (≥${kPrePedidoHorasAbandonoPotencial}h): ${operacionalStats.abandonadosPotencial} · '
                      'Substituídos: ${operacionalStats.substituidos} · '
                      'Histórico: ${operacionalStats.historicoEncerrado} · '
                      'Total: ${operacionalStats.total}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildListaPrePedidos(status: 'pendente'),
                        _buildListaPrePedidos(status: 'todos'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        floatingActionButton: FloatingActionButton(
          onPressed: _abrirSugestoesIaPedidos,
          tooltip: 'Sugestões com IA (entregas, pendências)',
          backgroundColor: Colors.amber,
          child: const Icon(Icons.auto_awesome, color: Colors.black87),
        ),
      );
      },
    );
  }

  List<Map<String, dynamic>> _filtrarEOrdenar(
    List<Map<String, dynamic>> lista,
    String? status,
  ) {
    var result = lista;
    final busca = _searchController.text.trim().toLowerCase();
    if (busca.isNotEmpty) {
      final buscaNum = busca.replaceAll(RegExp(r'[^\d]'), '');
      result = result.where((p) {
        final cliente = p['cliente'] as Map?;
        final nome = (cliente?['nome'] ?? '').toString().toLowerCase();
        final tel = (cliente?['telefone'] ?? '')
            .toString()
            .replaceAll(RegExp(r'[^\d]'), '');
        final id = (p['id'] ?? '').toString().toLowerCase();
        return nome.contains(busca) ||
            (buscaNum.isNotEmpty && tel.contains(buscaNum)) ||
            (busca.length >= 6 && id.contains(busca));
      }).toList();
    }
    if (_ordenacao == 'antigo') {
      result = List.from(result)
        ..sort(
            (a, b) => _compareData(a['dataCriacao'], b['dataCriacao'], false));
    } else if (_ordenacao == 'valor_maior') {
      result = List.from(result)
        ..sort((a, b) =>
            ((b['total'] as num?) ?? 0).compareTo((a['total'] as num?) ?? 0));
    } else if (_ordenacao == 'valor_menor') {
      result = List.from(result)
        ..sort((a, b) =>
            ((a['total'] as num?) ?? 0).compareTo((b['total'] as num?) ?? 0));
    } else {
      result = List.from(result)
        ..sort(
            (a, b) => _compareData(a['dataCriacao'], b['dataCriacao'], true));
    }
    // Ordem operacional: fila ativa → possível abandono → substituídos → histórico encerrado
    final fila = <Map<String, dynamic>>[];
    final aband = <Map<String, dynamic>>[];
    final subst = <Map<String, dynamic>>[];
    final hist = <Map<String, dynamic>>[];
    for (final p in result) {
      switch (classificarPrePedidoOperacional(p)) {
        case PrePedidoFilaOperacional.filaAtiva:
          fila.add(p);
          break;
        case PrePedidoFilaOperacional.potencialmenteAbandonado:
          aband.add(p);
          break;
        case PrePedidoFilaOperacional.substituidoGovernanca:
          subst.add(p);
          break;
        case PrePedidoFilaOperacional.historicoEncerrado:
          hist.add(p);
          break;
      }
    }
    return [...fila, ...aband, ...subst, ...hist];
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 12,
              width: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _compareData(dynamic a, dynamic b, bool recentePrimeiro) {
    try {
      final da = (a as dynamic).toDate() as DateTime;
      final db = (b as dynamic).toDate() as DateTime;
      return recentePrimeiro ? db.compareTo(da) : da.compareTo(db);
    } catch (_) {
      return 0;
    }
  }

  Widget _buildListaPrePedidos({String? status}) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PrePedidoService.streamPrePedidos(
        lojaId: widget.lojaId,
        status: status,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonLoading();
        }

        if (snapshot.hasError) {
          return _PrePedidosErroBody(
            errorMessage: '${snapshot.error}',
            onRetry: () => setState(() {}),
            primaryColor: _primaryColor,
            errorColor: _errorColor,
          );
        }

        final prePedidos = _filtrarEOrdenar(snapshot.data ?? [], status);

        // Abrir detalhe do pedido da notificação ("Ver pedido") para o admin concluir
        if (status == 'pendente' &&
            widget.initialPedidoId != null &&
            widget.initialPedidoId!.isNotEmpty &&
            !_initialPedidoHighlightShown &&
            prePedidos.isNotEmpty) {
          Map<String, dynamic>? pedidoNotif;
          for (final p in prePedidos) {
            if ((p['id'] ?? '').toString() == widget.initialPedidoId) {
              pedidoNotif = p;
              break;
            }
          }
          if (pedidoNotif != null) {
            final pedido = pedidoNotif;
            _initialPedidoHighlightShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _verDetalhes(pedido, abrirParaConcluir: true);
            });
          }
        }

        if (prePedidos.isEmpty) {
          return Center(
            child: _PrePedidosEmptyBody(
              isPendente: status == 'pendente',
              primaryColor: _primaryColor,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          color: _primaryColor,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: prePedidos.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final prePedido = prePedidos[index];
              return _buildPrePedidoCard(prePedido);
            },
          ),
        );
      },
    );
  }

  Widget _buildPrePedidoCard(Map<String, dynamic> prePedido) {
    final prePedidoId = prePedido['id'] ?? '';
    final status = normalizarStatusPrePedido(prePedido['status']);
    final statusPagamento =
        (prePedido['statusPagamento'] ?? 'pendente').toString();
    final cliente = prePedido['cliente'] as Map<String, dynamic>?;
    final itens =
        (prePedido['itens'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total = (prePedido['total'] as num?)?.toDouble() ?? 0.0;
    final pagamento = (prePedido['pagamento'] ?? '').toString();
    final dataCriacao = prePedido['dataCriacao'];
    final substituidoPor = prePedido['substituidoPor']?.toString();
    final isSubstituidoGovernanca =
        isGovernancaSubstituidoPrePedido(prePedido);
    final operacional = classificarPrePedidoOperacional(prePedido);
    final isAbandonoPotencial = operacional ==
        PrePedidoFilaOperacional.potencialmenteAbandonado;
    final isGateway = _isPagamentoGateway(pagamento);
    final aguardandoPagamento =
        isGateway && (statusPagamento == 'pendente' || status == 'pendente');

    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (status) {
      case 'paid':
      case 'pago':
        statusColor = _successColor;
        statusIcon = Icons.payment;
        statusLabel = 'Pago';
        break;
      case 'aprovado':
        statusColor = _successColor;
        statusIcon = Icons.verified;
        statusLabel = 'Aprovado';
        break;
      case 'finalizado':
        statusColor = _successColor;
        statusIcon = Icons.check_circle_outline;
        statusLabel = 'Finalizado';
        break;
      case 'confirmado':
        statusColor = _successColor;
        statusIcon = Icons.check_circle;
        statusLabel = 'Confirmado';
        break;
      case 'embalando':
      case 'em_preparacao':
        statusColor = Colors.blue;
        statusIcon = Icons.inventory_2;
        statusLabel = 'Em preparação';
        break;
      case 'enviado':
        statusColor = Colors.blue.shade700;
        statusIcon = Icons.local_shipping;
        statusLabel = 'Enviado';
        break;
      case 'entregue':
        statusColor = Colors.green;
        statusIcon = Icons.done_all;
        statusLabel = 'Entregue';
        break;
      case 'cancelado':
        statusColor = _errorColor;
        statusIcon = Icons.cancel;
        statusLabel = 'Cancelado';
        break;
      default:
        statusColor = _warningColor;
        statusIcon = Icons.pending;
        statusLabel = 'Pendente';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isAbandonoPotencial
            ? Border(
                left: BorderSide(
                  color: Colors.orange.shade400,
                  width: 4,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  statusColor.withOpacity(0.1),
                  statusColor.withOpacity(0.05)
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente?['nome'] ?? 'Cliente não informado',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            _formatarDataRelativa(dataCriacao),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      if (isSubstituidoGovernanca) ...[
                        const SizedBox(height: 4),
                        Text(
                          substituidoPor != null && substituidoPor.isNotEmpty
                              ? 'Substituído por #$substituidoPor'
                              : 'Substituído (nova tentativa de checkout)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (isAbandonoPotencial) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Possível abandono — sem atividade recente (≥${kPrePedidoHorasAbandonoPotencial}h; estimativa)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.brown.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Alerta: pedido da gateway aguardando confirmação de pagamento
          if (aguardandoPagamento)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _warningColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warningColor.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: _warningColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pagamento pendente. Verifique no app do banco se o pagamento foi concluído.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Corpo
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Itens
                Row(
                  children: [
                    const Icon(Icons.shopping_bag, size: 16, color: _primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Itens (${itens.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...itens.take(3).map((item) {
                  final nome = catalogPedidoItemDisplayName(
                      Map<String, dynamic>.from(item));
                  final qty = item['quantidade'] ?? 1;
                  final preco =
                      (item['precoUnitario'] as num?)?.toDouble() ?? 0.0;
                  final linhaVar = ProdutoVariacaoExtra.linhaVariacoesParaSeparacao(
                      Map<String, dynamic>.from(item));
                  final comboLegivel =
                      ComboConfiguravelResumo.textoParaItemMap(
                          Map<String, dynamic>.from(item));

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${qty}x',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              if (linhaVar.isNotEmpty)
                                Text(
                                  linhaVar,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              if (comboLegivel.isNotEmpty)
                                Text(
                                  comboLegivel,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          'R\$ ${preco.toStringAsFixed(2).replaceAll('.', ',')}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                }),
                if (itens.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+ ${itens.length - 3} item(ns)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),

                const Divider(height: 24),

                // Resumo financeiro
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _successColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.attach_money, color: _successColor),
                          SizedBox(width: 8),
                          Text(
                            'Total:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _successColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Info adicional + WhatsApp
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(Icons.payment, pagamento),
                    if (cliente != null &&
                        (cliente['telefone']?.toString() ?? '').isNotEmpty) ...[
                      _buildInfoChip(
                          Icons.phone, cliente['telefone'].toString()),
                      InkWell(
                        onTap: () => _abrirWhatsApp(
                          cliente['telefone'].toString(),
                          cliente['nome']?.toString() ?? 'Cliente',
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF25D366).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat,
                                  size: 14, color: Colors.green[700]),
                              const SizedBox(width: 6),
                              Text(
                                'WhatsApp',
                                style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          _buildCardAcoes(prePedido, status, prePedidoId),
        ],
      ),
    );
  }

  Widget _buildCardAcoes(
    Map<String, dynamic> prePedido,
    String status,
    String prePedidoId,
  ) {
    final isPendente = status == 'pendente';
    final isEncerrado = status == 'entregue' || status == 'cancelado';
    final podeAtualizar = podeExibirAtualizacaoStatusOperacional(status);
    final pagoGateway = isPrePedidoPagamentoGatewayConcluido(prePedido);

    final verBtn = Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _verDetalhes(prePedido),
        icon: const Icon(Icons.visibility, size: 18),
        label: const Text('Ver'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryColor,
          side: const BorderSide(color: _primaryColor),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );

    final List<Widget> extras;
    if (isPendente && !pagoGateway) {
      extras = [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _confirmarPedido(prePedido),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _successColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _cancelarPedido(prePedidoId),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancelar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _errorColor,
              side: const BorderSide(color: _errorColor),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ];
    } else if (podeAtualizar || (isPendente && pagoGateway)) {
      extras = [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => _mostrarDialogoAtualizarStatus(prePedido),
            icon: const Icon(Icons.update, size: 18),
            label: const Text('Atualizar status'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ];
    } else if (isEncerrado) {
      extras = [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _excluirPedidoFinalizado(prePedido),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Excluir'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _errorColor,
              side: const BorderSide(color: _errorColor),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ];
    } else {
      extras = const [];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          verBtn,
          if (extras.isNotEmpty) const SizedBox(width: 8),
          ...extras,
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verDetalhes(Map<String, dynamic> prePedido,
      {bool abrirParaConcluir = false}) async {
    final prePedidoId = (prePedido['id'] ?? '').toString();
    Map<String, dynamic> dados = Map<String, dynamic>.from(prePedido);
    if (prePedidoId.isNotEmpty) {
      final fresh = await PrePedidoService.buscarPrePedido(
        lojaId: widget.lojaId,
        prePedidoId: prePedidoId,
      );
      if (fresh != null) dados = fresh;
    }

    final url = PrePedidoService.gerarUrlPedido(
      prePedidoId: prePedidoId,
      lojaId: widget.lojaId,
    );
    final status = normalizarStatusPrePedido(dados['status']);
    final isPendente = status == 'pendente';
    final pagoGateway = isPrePedidoPagamentoGatewayConcluido(dados);
    final podeAtualizar =
        podeExibirAtualizacaoStatusOperacional(status) ||
        (isPendente && pagoGateway);
    final total = (dados['total'] as num?)?.toDouble() ?? 0.0;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.receipt_long, color: _primaryColor),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Detalhes do Pedido',
                        style:
                            TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle(Icons.info_outline, 'Pedido'),
                      const SizedBox(height: 8),
                      _buildDetalhePedidoResumo(dados, total),

                      const SizedBox(height: 24),

                      _buildSectionTitle(Icons.person, 'Cliente'),
                      const SizedBox(height: 8),
                      _buildDetalheCliente(dados['cliente']),

                      const SizedBox(height: 24),

                      _buildSectionTitle(Icons.shopping_bag, 'Itens'),
                      const SizedBox(height: 8),
                      _buildDetalheItens(dados['itens']),

                      const SizedBox(height: 24),

                      _buildSectionTitle(Icons.local_shipping, 'Entrega'),
                      const SizedBox(height: 8),
                      _buildDetalheEntrega(dados['frete']),

                      if (_temShippingPreOrder(dados)) ...[
                        const SizedBox(height: 16),
                        _buildShippingPreOrderSection(dados),
                      ],

                      const SizedBox(height: 24),

                      _buildSectionTitle(Icons.payment, 'Pagamento'),
                      const SizedBox(height: 8),
                      _buildDetalhePagamento(dados),

                      const SizedBox(height: 24),

                      // Link
                      _buildSectionTitle(Icons.link, 'Link do Pedido'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: url));
                          _showModernSnackBar(
                              'Link copiado para a área de transferência!');
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _primaryColor.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  url,
                                  style: const TextStyle(
                                    color: _primaryColor,
                                    decoration: TextDecoration.underline,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.copy,
                                    size: 18, color: _primaryColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (abrirParaConcluir && isPendente && !pagoGateway)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _confirmarPedido(dados);
                        },
                        icon: const Icon(Icons.check_circle, size: 22),
                        label: const Text(
                          'Confirmar pedido',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _successColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (podeAtualizar)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _mostrarDialogoAtualizarStatus(dados);
                        },
                        icon: const Icon(Icons.update, size: 22),
                        label: const Text(
                          'Atualizar status',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildDetalhePedidoResumo(Map<String, dynamic> dados, double total) {
    final st = normalizarStatusPrePedido(dados['status']);
    final orderId = (dados['id'] ?? dados['orderId'] ?? '-').toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetalheRow(Icons.tag, 'Pedido', orderId),
          _buildDetalheRow(Icons.flag, 'Status', st),
          _buildDetalheRow(
            Icons.attach_money,
            'Total',
            'R\$ ${total.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }

  Widget _buildDetalhePagamento(Map<String, dynamic> dados) {
    final pagamento = (dados['pagamento'] ?? '-').toString();
    final statusPagamento =
        (dados['statusPagamento'] ?? 'pendente').toString();
    final paymentId = (dados['paymentId'] ?? '').toString();
    final mpStatus = (dados['mpPaymentStatus'] ?? '').toString();
    String paidAtStr = '-';
    final paidAt = dados['paidAt'];
    if (paidAt != null) {
      try {
        final dt = (paidAt as dynamic).toDate() as DateTime;
        paidAtStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        paidAtStr = paidAt.toString();
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetalheRow(Icons.payment, 'Forma', pagamento),
          _buildDetalheRow(
              Icons.verified_user, 'Status pag.', statusPagamento),
          if (paymentId.isNotEmpty)
            _buildDetalheRow(Icons.receipt, 'Payment ID', paymentId),
          if (mpStatus.isNotEmpty)
            _buildDetalheRow(Icons.account_balance, 'MP status', mpStatus),
          if (paidAt != null)
            _buildDetalheRow(Icons.schedule, 'Pago em', paidAtStr),
        ],
      ),
    );
  }

  Widget _buildDetalheCliente(Map<String, dynamic>? cliente) {
    if (cliente == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Não informado'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetalheRow(
              Icons.person_outline, 'Nome', cliente['nome'] ?? '-'),
          _buildDetalheRow(Icons.phone, 'Telefone', cliente['telefone'] ?? '-'),
          _buildDetalheRow(Icons.email, 'Email', cliente['email'] ?? '-'),
          _buildDetalheRow(Icons.location_on, 'Endereço',
              cliente['enderecoFormatado'] ?? '-'),
        ],
      ),
    );
  }

  Widget _buildDetalheRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheItens(List? itens) {
    if (itens == null || itens.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Nenhum item'),
      );
    }

    return Column(
      children: itens.map((item) {
        final nome = catalogPedidoItemDisplayName(
            Map<String, dynamic>.from(item));
        final qty = item['quantidade'] ?? 1;
        final preco = (item['precoUnitario'] as num?)?.toDouble() ?? 0.0;
        final total = (item['total'] as num?)?.toDouble() ?? 0.0;
        final linhaVar = ProdutoVariacaoExtra.linhaVariacoesParaSeparacao(
            Map<String, dynamic>.from(item));
        final comboLegivelDet =
            ComboConfiguravelResumo.textoParaItemMap(
                Map<String, dynamic>.from(item));

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${qty}x',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: _primaryColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (linhaVar.isNotEmpty)
                      Text(linhaVar,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (comboLegivelDet.isNotEmpty)
                      Text(
                        comboLegivelDet,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    Text(
                      'R\$ ${preco.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Text(
                'R\$ ${total.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: _successColor),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _nomeEntregaComPlataforma(Map<String, dynamic> frete) {
    final nome = frete['nome'] ?? 'Entrega';
    final plat = (frete['plataforma'] ?? '').toString().trim();
    if (plat.isEmpty || plat == 'manual') return nome;
    final abbr = plat == 'melhor_envio'
        ? 'ME'
        : plat == 'superfrete'
            ? 'SF'
            : plat == 'frenet'
                ? 'Frenet'
                : '';
    return abbr.isEmpty ? nome : '$nome $abbr';
  }

  Widget _buildDetalheEntrega(Map<String, dynamic>? frete) {
    if (frete == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Não informado'),
      );
    }

    final nome = _nomeEntregaComPlataforma(frete);
    final valor = (frete['valor'] as num?)?.toDouble() ?? 0.0;
    final gratis = frete['gratis'] == true;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping, color: _primaryColor),
          const SizedBox(width: 12),
          Expanded(child: Text(nome)),
          Text(
            gratis ? 'GRÁTIS' : 'R\$ ${valor.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: gratis ? _successColor : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  bool _temShippingPreOrder(Map<String, dynamic> dados) {
    final frete = dados['frete'];
    final plataforma = frete is Map
        ? (frete['plataforma'] ?? '').toString().trim()
        : '';
    if (plataforma == 'superfrete' || plataforma == 'melhor_envio') {
      return true;
    }
    return dados['shippingPreOrder'] is Map;
  }

  Widget _buildShippingPreOrderSection(Map<String, dynamic> dados) {
    final shipping = dados['shippingPreOrder'] is Map
        ? Map<String, dynamic>.from(dados['shippingPreOrder'] as Map)
        : <String, dynamic>{};
    final frete = dados['frete'] is Map
        ? Map<String, dynamic>.from(dados['frete'] as Map)
        : <String, dynamic>{};
    final provider =
        (shipping['provider'] ?? frete['plataforma'] ?? '').toString();
    final status = (shipping['status'] ?? 'pending').toString();
    final errorCode = shipping['errorCode']?.toString();
    final isSuperFrete = provider == 'superfrete';
    final isExternalUnknown = status == 'external_state_unknown';
    final canRetry = !isExternalUnknown
        && (status == 'failed' || status == 'needs_product_data');
    final canManualConfirm =
        isSuperFrete && isExternalUnknown && status != 'created';
    final statusLabel =
        ShippingPreOrderService.statusLabel(status, provider: provider);
    final providerLabel = ShippingPreOrderService.providerLabel(provider);
    final errorMsg = isExternalUnknown
        ? ShippingPreOrderService.externalStateUnknownGuidance()
        : ShippingPreOrderService.messageForErrorCode(errorCode);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pré-pedido de envio',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text('$providerLabel: $statusLabel'),
          if (status == 'created' &&
              (shipping['providerReference'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Referência: ${shipping['providerReference']}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          if (errorMsg.isNotEmpty && status != 'created')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                errorMsg,
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          if (canRetry) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _retryShippingPreOrder(dados),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Criar novamente pré-pedido'),
              ),
            ),
          ],
          if (canManualConfirm) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _confirmSuperFreteCartManual(dados),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Marcar como carrinho criado'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _retryShippingPreOrder(Map<String, dynamic> dados) async {
    final pedidoId = dados['id']?.toString() ?? '';
    if (pedidoId.isEmpty) return;
    _showModernSnackBar('Criando pré-pedido de envio...');
    final res = await ShippingPreOrderService.retryPreOrder(
      lojaId: widget.lojaId,
      orderId: pedidoId,
    );
    if (!mounted) return;
    if (res['ok'] == true) {
      _showModernSnackBar('Pré-pedido de envio criado com sucesso.');
      setState(() {});
    } else {
      final msg = (res['message'] ?? 'Não foi possível criar o pré-pedido.')
          .toString();
      _showModernSnackBar(msg);
    }
  }

  Future<void> _confirmSuperFreteCartManual(Map<String, dynamic> dados) async {
    final pedidoId = dados['id']?.toString() ?? '';
    if (pedidoId.isEmpty) return;

    final controller = TextEditingController();
    final cartId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como carrinho criado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informe o identificador do carrinho exibido no painel da SuperFrete. '
              'Esta ação não cria um novo carrinho na transportadora.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'ID do carrinho SuperFrete',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (cartId == null || cartId.isEmpty || !mounted) return;

    _showModernSnackBar('Salvando confirmação...');
    final res = await ShippingPreOrderService.confirmSuperFreteCartCreated(
      lojaId: widget.lojaId,
      orderId: pedidoId,
      providerCartId: cartId,
    );
    if (!mounted) return;
    if (res['ok'] == true) {
      _showModernSnackBar('Carrinho marcado como criado.');
      setState(() {});
    } else {
      _showModernSnackBar(
        (res['message'] ?? 'Não foi possível confirmar.').toString(),
      );
    }
  }

  Future<void> _mostrarDialogoAtualizarStatus(
      Map<String, dynamic> prePedido) async {
    final prePedidoId = prePedido['id']?.toString() ?? '';
    final statusAtual = normalizarStatusPrePedido(prePedido['status']);
    var opcoes = opcoesProximoStatusOperacional(statusAtual);
    if (opcoes.isEmpty && isPrePedidoPagamentoGatewayConcluido(prePedido)) {
      opcoes = opcoesProximoStatusOperacional('paid');
    }

    if (opcoes.isEmpty) return;

    final selecionado = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Atualizar status do pedido',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ...opcoes.map((opt) => ListTile(
                  leading: Icon(
                    opt['valor'] == 'em_preparacao' || opt['valor'] == 'embalando'
                        ? Icons.inventory_2
                        : opt['valor'] == 'enviado'
                            ? Icons.local_shipping
                            : Icons.done_all,
                    color: _primaryColor,
                  ),
                  title: Text(opt['label'] ?? ''),
                  onTap: () => Navigator.pop(context, opt['valor']),
                )),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );

    if (selecionado == null || selecionado.isEmpty) return;

    // Enviado/postado: tipo explícito (Correios vs entrega local) + código se necessário
    Map<String, dynamic>? extraUpdates;
    if (selecionado == 'enviado') {
      if (!mounted) return;
      final envioResult = await _mostrarDialogoTipoEnvioEnviado(context);
      if (!mounted) return;
      if (envioResult == null) return;
      final tipo = envioResult['tipoEntregaEnvio'] as String? ?? '';
      if (tipo == 'rastreio') {
        final codigo = (envioResult['codigoRastreio'] as String?)?.trim() ?? '';
        extraUpdates = {
          'tipoEntregaEnvio': 'rastreio',
          'codigoRastreio': codigo,
        };
      } else if (tipo == 'local') {
        extraUpdates = {
          'tipoEntregaEnvio': 'local',
        };
      } else if (tipo == 'retirada') {
        extraUpdates = {
          'tipoEntregaEnvio': 'retirada',
        };
      } else {
        return;
      }
    }

    try {
      final ok =
          await PrePedidoService.atualizarStatusOperacionalPedidoCatalogo(
        lojaId: widget.lojaId,
        pedidoId: prePedidoId,
        novoStatus: selecionado,
        extraUpdates: extraUpdates,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Status atualizado para: ${opcoes.firstWhere((o) => o['valor'] == selecionado, orElse: () => {
                      'label': selecionado
                    })['label']}'),
            backgroundColor: _successColor,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Erro ao atualizar status'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Tipo de envio ao marcar "Enviado / postado" (e-mail via Cloud Function).
  /// `tipoEntregaEnvio`: rastreio | local | retirada
  Future<Map<String, dynamic>?> _mostrarDialogoTipoEnvioEnviado(
    BuildContext context,
  ) async {
    final controller = TextEditingController();
    String? modo; // rastreio | local | retirada
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (_, setDialogState) => AlertDialog(
            title: const Text('Enviado / postado'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tipo de envio',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    title: const Text('Correios / transportadora'),
                    value: 'rastreio',
                    groupValue: modo,
                    onChanged: (v) => setDialogState(() => modo = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: const Text('Entrega local'),
                    subtitle: const Text(
                      'Motoboy ou entrega própria, sem rastreio dos Correios.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: 'local',
                    groupValue: modo,
                    onChanged: (v) => setDialogState(() => modo = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    title: const Text('Retirada / combinar com a loja'),
                    subtitle: const Text(
                      'Cliente busca no endereço combinado; mensagem de e-mail sem “saiu para entrega”.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: 'retirada',
                    groupValue: modo,
                    onChanged: (v) => setDialogState(() => modo = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (modo == 'rastreio') ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Código de rastreio (obrigatório)',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Código (ex: AA123456789BR)',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (modo == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Selecione o tipo de envio.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  if (modo == 'rastreio') {
                    final codigo = controller.text.trim();
                    if (codigo.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Informe o código de rastreio para envio pelos Correios ou transportadora.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, {
                      'tipoEntregaEnvio': 'rastreio',
                      'codigoRastreio': codigo,
                    });
                    return;
                  }
                  if (modo == 'retirada') {
                    Navigator.pop(dialogContext, {
                      'tipoEntregaEnvio': 'retirada',
                    });
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'tipoEntregaEnvio': 'local',
                  });
                },
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      );
      return result;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _confirmarPedido(Map<String, dynamic> prePedido) async {
    final confirmar = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _successColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, size: 48, color: _successColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirmar Pedido',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Ao confirmar, este pedido será registrado como venda no sistema.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirmar'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );

    if (confirmar != true) return;
    if (_confirmandoPedido) return;

    _confirmandoPedido = true;
    try {
      final prePedidoId = prePedido['id']?.toString().trim() ?? '';
      if (prePedidoId.isEmpty) {
        throw Exception('Pré-pedido sem identificador.');
      }

      final itensParaVenda = (prePedido['itens'] as List).map((item) {
        final precoUnit = (item['precoUnitario'] as num?)?.toDouble() ?? 0.0;
        logD('[PRE-PEDIDO] Processando item: ${item['nome']}');
        logD('[PRE-PEDIDO]   - precoUnitario: $precoUnit');
        logD('[PRE-PEDIDO]   - tamanho: ${item['tamanho']}');
        logD('[PRE-PEDIDO]   - cor: ${item['cor']}');
        logD('[PRE-PEDIDO]   - quantidade: ${item['quantidade']}');

        final productId = (item['productId'] ?? item['id'] ?? item['produtosId'] ?? '')
            .toString()
            .trim();
        final nomeItem = catalogPedidoItemDisplayName(
            Map<String, dynamic>.from(item));
        return {
          'nome': nomeItem,
          'name': nomeItem,
          'productId': productId,
          'id': productId,
          'produtosId': item['produtosId'] ?? productId,
          'quantidade': item['quantidade'] ?? 1,
          'qty': item['quantidade'] ?? 1,
          'preco': precoUnit,
          'price': precoUnit,
          'precoUnitario': precoUnit,
          'tamanho': item['tamanho'] ?? '',
          'size': item['tamanho'] ?? '',
          'cor': item['cor'] ?? '',
          'color': item['cor'] ?? '',
          'slug': item['slug'] ?? '',
          'imageUrl': item['imagem'] ?? item['imageUrl'] ?? '',
          'percentualDescontoPix': 0.0, // já aplicado em precoUnitario
          if ((item['variacaoExtraResumo'] ?? '').toString().trim().isNotEmpty)
            'variacaoExtraResumo':
                (item['variacaoExtraResumo'] ?? '').toString().trim(),
          if ((item['extraValor'] ?? '').toString().trim().isNotEmpty)
            'extraValor': (item['extraValor'] ?? '').toString().trim(),
          if ((item['extraTipo'] ?? '').toString().trim().isNotEmpty)
            'extraTipo': (item['extraTipo'] ?? '').toString().trim(),
          if ((item['comboConfiguravelResumo'] ?? '').toString().trim().isNotEmpty)
            'comboConfiguravelResumo':
                (item['comboConfiguravelResumo'] ?? '').toString().trim(),
          ...(() {
            final raw = item['itensComboComSelecao'];
            if (raw is! List || raw.isEmpty) return <String, dynamic>{};
            final copies = <Map<String, dynamic>>[];
            for (final e in raw) {
              if (e is Map) {
                copies.add(
                  Map<String, dynamic>.from(
                    e.map((k, v) => MapEntry(k.toString(), v)),
                  ),
                );
              }
            }
            if (copies.isEmpty) return <String, dynamic>{};
            return <String, dynamic>{'itensComboComSelecao': copies};
          })(),
        };
      }).toList();

      logD(
          '[PRE-PEDIDO] Total de itens para venda: ${itensParaVenda.length}');

      final totalPedido = (prePedido['total'] as num?)?.toDouble();
      final freteMap =
          prePedido['frete'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final freteGratis = freteMap['freteGratis'] == true;
      final freteValor = freteGratis
          ? 0.0
          : (freteMap['valor'] as num?)?.toDouble() ?? 0.0;
      final pagamento = (prePedido['pagamento'] ?? 'PIX').toString();
      final totalPago = totalPedido ??
          itensParaVenda.fold<double>(
            0,
            (acc, item) =>
                acc +
                ((item['precoUnitario'] as num?)?.toDouble() ?? 0) *
                    ((item['quantidade'] as num?)?.toInt() ?? 1),
          ) +
              freteValor;

      double dinheiro = 0, pix = 0, cartao = 0;
      switch (pagamento.toUpperCase()) {
        case 'PIX':
          pix = totalPago;
          break;
        case 'CARTÃO':
        case 'CARTAO':
        case 'MERCADO PAGO':
          cartao = totalPago;
          break;
        case 'DINHEIRO':
          dinheiro = totalPago;
          break;
        default:
          pix = totalPago;
      }

      final vendaItens = <VendaItem>[
        for (final item in itensParaVenda)
          VendaItem(
            produtoNome: (item['nome'] ?? '').toString(),
            quantidade: (item['quantidade'] as int?) ??
                (item['qty'] as int?) ??
                1,
            precoUnitario: (item['precoUnitario'] as num?)?.toDouble() ??
                (item['preco'] as num?)?.toDouble() ??
                0,
            tamanho: (item['tamanho'] ?? '').toString(),
            cor: (item['cor'] ?? '').toString(),
            lojaId: widget.lojaId,
            productId: () {
              final pid = (item['productId'] ?? '').toString().trim();
              return pid.isNotEmpty ? pid : null;
            }(),
            variacaoExtraResumo:
                (item['variacaoExtraResumo'] ?? '').toString().trim(),
          ),
      ];

      Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice;
      for (var i = 0; i < itensParaVenda.length; i++) {
        final raw = itensParaVenda[i]['itensComboComSelecao'];
        if (raw is! List || raw.isEmpty) continue;
        final copies = <Map<String, dynamic>>[];
        for (final e in raw) {
          if (e is Map) {
            copies.add(
              Map<String, dynamic>.from(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }
        if (copies.isNotEmpty) {
          itensComboSelecaoPorIndice ??= {};
          itensComboSelecaoPorIndice[i] = copies;
        }
      }

      final produtosBox =
          await Hive.openBox<Produto>(HiveBoxNames.produtos(widget.lojaId));
      final clientesBox =
          await Hive.openBox<Cliente>(HiveBoxNames.clientes(widget.lojaId));
      final vendasBox =
          await Hive.openBox<Venda>(HiveBoxNames.vendas(widget.lojaId));

      final clienteMap =
          prePedido['cliente'] as Map<String, dynamic>? ?? <String, dynamic>{};

      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: (clienteMap['nome'] ?? 'Cliente').toString(),
        itens: vendaItens,
        dinheiro: dinheiro,
        pix: pix,
        cartao: cartao,
        vendedor: 'Loja online',
        observacao: (prePedido['observacao'] ?? '').toString(),
        frete: freteValor,
        descontoPct: 0,
        lojaId: widget.lojaId,
        itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
        saleIntentId: PrePedidoSaleIntent.saleIntentIdForPedido(prePedidoId),
        saleIntentOrigin: PrePedidoSaleIntent.origin,
      );

      final vendaId = venda.key.toString();

      final subtotalPedido = (prePedido['subtotal'] as num?)?.toDouble() ??
          itensParaVenda.fold<double>(
            0,
            (acc, item) =>
                acc +
                ((item['precoUnitario'] as num?)?.toDouble() ?? 0) *
                    ((item['quantidade'] as num?)?.toInt() ?? 1),
          );

      await CatalogoPedidoHistoricoService().garantirDocumentoPedidosHistorico(
        lojaId: widget.lojaId,
        vendaId: vendaId,
        customer: clienteMap,
        items: itensParaVenda,
        entrega: freteMap,
        pagamento: pagamento,
        subtotal: subtotalPedido,
        total: totalPago,
        observacao: (prePedido['observacao'] ?? '').toString(),
        cupom: prePedido['cupom'] as Map<String, dynamic>?,
        premioRoletaRaw: prePedido['premioRoleta'] as Map<String, dynamic>?,
      );

      await CatalogoVendaSideEffectsSecundariosService()
          .aplicarAposVendaCatalogoAdmin(
        lojaId: widget.lojaId,
        venda: venda,
        vendaId: vendaId,
        customer: clienteMap,
        items: itensParaVenda,
        produtosBox: produtosBox,
        total: totalPago,
        premioRoletaRaw: prePedido['premioRoleta'] as Map<String, dynamic>?,
        vendedorNome: prePedido['vendedorRef']?.toString(),
      );

      await PrePedidoService.confirmarPrePedido(
        lojaId: widget.lojaId,
        prePedidoId: prePedidoId,
        vendaId: vendaId,
      );

      // Gerar número da sorte e enviar por email e WhatsApp ao cliente
      final cliente = clienteMap;
      final itens = prePedido['itens'] as List<dynamic>? ?? [];
      var valorTotal = totalPago;
      if (valorTotal <= 0 && itens.isNotEmpty) {
        valorTotal = 0;
        for (final e in itens) {
          final m = e as Map<String, dynamic>;
          valorTotal += ((m['precoUnitario'] as num?)?.toDouble() ?? 0) *
              ((m['quantidade'] as num?)?.toInt() ?? 1);
        }
      }
      final posPagamentoOk =
          await PosPagamentoService.processarConfirmacaoPagamento(
        lojaId: widget.lojaId,
        vendaId: vendaId,
        customer: {
          'nome': cliente['nome'] ?? '',
          'email': cliente['email'] ?? '',
          'telefone': cliente['telefone'] ?? cliente['tel'] ?? '',
          'id': cliente['id'] ?? cliente['clienteId'],
        },
        items: itensParaVenda,
        valorTotal: valorTotal,
        formaPagamento: pagamento,
        cupomRoletaCodigo: prePedido['premioRoleta']?['codigo']?.toString(),
        cupomRoletaDesconto:
            (prePedido['premioRoleta']?['valor'] as num?)?.toDouble(),
        estoqueJaBaixado: true,
      );

      if (mounted) {
        if (posPagamentoOk) {
          _showModernSnackBar(
            'Pedido confirmado e venda registrada! Número da sorte enviado por email e WhatsApp.',
          );
        } else {
          final detalhe = PosPagamentoService.ultimaFalhaProcessamento ?? '';
          final lower = detalhe.toLowerCase();
          final msg = lower.contains('estoque insuficiente')
              ? 'Pagamento confirmado, mas o estoque é insuficiente: $detalhe'
              : lower.contains('informe o tamanho') ||
                      lower.contains('variação de tamanho') ||
                      lower.contains('tamanho e cor')
                  ? 'Pagamento confirmado, mas falta tamanho/cor no pedido: $detalhe'
                  : detalhe.isNotEmpty
                      ? 'Pagamento confirmado, mas houve falha no pós-pagamento: $detalhe'
                      : 'Pagamento confirmado, mas houve falha ao processar o pós-pagamento (notificações). Tente novamente.';
          _showModernSnackBar(msg, isError: true);
        }
      }
    } catch (e, st) {
      logE('[PRE-PEDIDO] ❌ ERRO ao confirmar pedido (type=${e.runtimeType})', error: e, st: st);

      if (mounted) {
        _showModernSnackBar('Erro ao confirmar pedido: $e', isError: true);
      }
    } finally {
      _confirmandoPedido = false;
    }
  }

  Future<void> _excluirPedidoFinalizado(Map<String, dynamic> prePedido) async {
    final prePedidoId = prePedido['id']?.toString() ?? '';
    final status = prePedido['status']?.toString() ?? '';
    final clienteNome = (prePedido['cliente'] as Map?)?['nome'] ?? 'Pedido';

    final confirmar = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, size: 48, color: _errorColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Excluir Pedido',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Excluir "$clienteNome" (${status.toUpperCase()})? Usado para limpar pedidos de teste.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Excluir'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );

    if (confirmar != true) return;

    try {
      final ok = await PrePedidoService.excluirPrePedido(
        lojaId: widget.lojaId,
        prePedidoId: prePedidoId,
      );
      if (!mounted) return;
      if (ok) {
        _showModernSnackBar('Pedido excluído.', isWarning: false);
      } else {
        _showModernSnackBar('Erro ao excluir pedido.', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showModernSnackBar('Erro: $e', isError: true);
    }
  }

  Future<void> _cancelarPedido(String prePedidoId) async {
    final motivoCtrl = TextEditingController();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _errorColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cancel, size: 48, color: _errorColor),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cancelar Pedido',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Tem certeza? Informe o motivo (opcional):',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: motivoCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Ex: Cliente desistiu, estoque indisponível...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, {'confirm': false}),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Não'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, {
                        'confirm': true,
                        'motivo': motivoCtrl.text.trim().isNotEmpty
                            ? motivoCtrl.text.trim()
                            : 'Cancelado pelo vendedor',
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _errorColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Sim, cancelar'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );

    if (result == null || result['confirm'] != true) return;

    try {
      await PrePedidoService.cancelarPrePedido(
        lojaId: widget.lojaId,
        prePedidoId: prePedidoId,
        motivo: '${result['motivo'] ?? 'Cancelado pelo vendedor'}',
      );

      if (mounted) {
        _showModernSnackBar('Pedido cancelado', isWarning: true);
      }
    } catch (e) {
      if (mounted) {
        _showModernSnackBar('Erro ao cancelar: $e', isError: true);
      }
    }
  }
}

/// Widget apenas visual: estado de erro ao carregar pedidos (com botão tentar novamente).
class _PrePedidosErroBody extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final Color primaryColor;
  final Color errorColor;

  const _PrePedidosErroBody({
    required this.errorMessage,
    required this.onRetry,
    required this.primaryColor,
    required this.errorColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 48, color: errorColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Erro ao carregar pedidos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget apenas visual: empty state da lista de pré-pedidos (sem botão).
class _PrePedidosEmptyBody extends StatelessWidget {
  final bool isPendente;
  final Color primaryColor;

  const _PrePedidosEmptyBody({
    required this.isPendente,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isPendente ? 'Nenhum pré-pedido pendente' : 'Nenhum pré-pedido encontrado',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isPendente ? 'Os novos pedidos aparecerão aqui' : 'Ainda não há pedidos registrados',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }
}

/// Widget apenas visual: banner "Sem conexão" (offline).
class _PrePedidosOfflineBanner extends StatelessWidget {
  final Color warningColor;

  const _PrePedidosOfflineBanner({required this.warningColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: warningColor.withOpacity(0.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 18, color: warningColor),
          const SizedBox(width: 8),
          Text(
            'Sem conexão',
            style: TextStyle(
              color: warningColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tela cheia de sugestões com IA – Pedidos.
class _SugestoesIaPedidosScreen extends StatefulWidget {
  final String resumoInicial;

  const _SugestoesIaPedidosScreen({required this.resumoInicial});

  @override
  State<_SugestoesIaPedidosScreen> createState() => _SugestoesIaPedidosScreenState();
}

class _SugestoesIaPedidosScreenState extends State<_SugestoesIaPedidosScreen> {
  final _perguntaCtrl = TextEditingController();
  String? _resposta;
  bool _enviando = false;
  static const _primaryColor = Color(0xFF6366F1);
  static const _cardColor = Color(0xFF1E293B);

  @override
  void dispose() {
    _perguntaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar(String? perguntaFixa) async {
    final pergunta = perguntaFixa ?? _perguntaCtrl.text.trim();
    if (pergunta.isEmpty || _enviando) return;
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() { _enviando = true; _resposta = null; });
    try {
      final resposta = await AiLojaService.analiseVendasNatural(
        pergunta: pergunta,
        resumoVendas: widget.resumoInicial,
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() { _resposta = resposta; _enviando = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cardColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        title: const Text('IA – Pedidos', style: TextStyle(color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        actions: const [
          AppHelpIconButton(iconColor: Colors.white),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _enviando ? null : () => _enviar(null),
        tooltip: 'Enviar pergunta',
        backgroundColor: _primaryColor,
        child: _enviando
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send, color: Colors.white),
      ),
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom + 100,
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sugestões sobre entregas, pendências e fluxo de pedidos. Contexto da tela já enviado.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Sugestões para reduzir atrasos nas entregas e melhorar prazo.'),
                  icon: const Icon(Icons.local_shipping, size: 18),
                  label: const Text('Entregas e prazos'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withOpacity(0.15)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Como organizar e priorizar pedidos pendentes? Sugestões.'),
                  icon: const Icon(Icons.pending_actions, size: 18),
                  label: const Text('Pedidos pendentes'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withOpacity(0.15)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Sugestões de mensagem ou comunicação com o cliente sobre status do pedido.'),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Comunicação com cliente'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withOpacity(0.15)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _perguntaCtrl,
              decoration: InputDecoration(
                hintText: 'Ex: Como evitar pedidos cancelados?',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
              ),
              maxLines: 2,
              enabled: !_enviando,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _enviando ? null : () => _enviar(null),
              icon: _enviando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
              label: Text(_enviando ? 'Analisando…' : 'Enviar'),
              style: FilledButton.styleFrom(backgroundColor: _primaryColor),
            ),
            if (_resposta != null) ...[
              const SizedBox(height: 24),
              const Text('Resposta:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    child: SelectableText(_resposta!, style: const TextStyle(color: Colors.white, height: 1.5, fontSize: 15)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 120),
          ],
        ),
        ),
      ),
    );
  }
}

