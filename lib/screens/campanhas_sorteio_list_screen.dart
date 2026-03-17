import 'package:android_intent_plus/android_intent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:intl/intl.dart';

import 'campanha_sorteio_form_screen.dart';
import 'globo_sorteio_screen.dart';
import 'campanha_sorteio_historico_screen.dart';
import 'roleta_sorte_config_screen.dart';

class CampanhasSorteioListScreen extends StatefulWidget {
  final String lojaId;

  const CampanhasSorteioListScreen({
    super.key,
    required this.lojaId,
  });

  @override
  State<CampanhasSorteioListScreen> createState() => _CampanhasSorteioListScreenState();
}

class _CampanhasSorteioListScreenState extends State<CampanhasSorteioListScreen>
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

  final _buscaController = TextEditingController();
  String _busca = '';
  String _filtroStatus = 'todas'; // todas | ativas | pausadas | finalizadas
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
    Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _isOffline = r.length == 1 && r.first == ConnectivityResult.none);
    });
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _isOffline = r.length == 1 && r.first == ConnectivityResult.none);
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _showModernSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? _errorColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Exclui uma campanha após confirmação
  Future<void> _excluirCampanha(String campanhaId, String nomeCampanha) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir campanha?'),
        content: Text(
          'A campanha "$nomeCampanha" será excluída permanentemente.\n\n'
          'Participantes e histórico de sorteios serão removidos. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _errorColor),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final campanhaRef = FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId);

      // Excluir subcoleções primeiro (participantes, historico_sorteios)
      final participantesSnap = await campanhaRef.collection('participantes').get();
      for (final doc in participantesSnap.docs) {
        await doc.reference.delete();
      }
      final historicoSnap = await campanhaRef.collection('historico_sorteios').get();
      for (final doc in historicoSnap.docs) {
        await doc.reference.delete();
      }

      await campanhaRef.delete();
      _showModernSnackBar('Campanha excluída com sucesso!');
      if (mounted) setState(() {});
    } catch (e) {
      _showModernSnackBar('Erro ao excluir campanha: $e', isError: true);
    }
  }

  /// Ativa ou desativa uma campanha
  Future<void> _toggleCampanhaAtiva(String campanhaId, bool novoValor, String nomeCampanha) async {
    if (!novoValor) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Desativar campanha?'),
          content: Text(
            'A campanha "$nomeCampanha" será pausada. Os participantes já cadastrados permanecem. Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _errorColor),
              child: const Text('Desativar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .doc(campanhaId)
          .update({
        'ativa': novoValor,
        'status': novoValor ? 'aberta' : 'pausada',
      });

      _showModernSnackBar(
        novoValor ? 'Campanha ativada com sucesso!' : 'Campanha desativada',
      );
    } catch (e) {
      _showModernSnackBar('Erro ao atualizar campanha: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceColor,
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: _warningColor.withValues(alpha:0.2),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 18, color: _warningColor),
                  SizedBox(width: 8),
                  Text('Sem conexão', style: TextStyle(color: _warningColor, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          Expanded(
            child: FadeTransition(
        opacity: _fadeAnimation,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: _primaryColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
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
                            color: Colors.white.withValues(alpha:0.1),
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
                            color: Colors.white.withValues(alpha:0.1),
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
                              'Sorteios e Campanhas',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gerencie suas campanhas e roleta da sorte',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha:0.9),
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
                    color: Colors.white.withValues(alpha:0.15),
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
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event, size: 18),
                            SizedBox(width: 8),
                            Text('Campanhas'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.casino, size: 18),
                            SizedBox(width: 8),
                            Text('Roleta da Sorte'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildCampanhasTab(),
              RoletaSorteConfigScreen(lojaId: widget.lojaId),
            ],
          ),
        ),
      ),
    ),
  ],
),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          return AnimatedOpacity(
            opacity: _tabController.index == 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: _tabController.index == 0 ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.extended(
                backgroundColor: _successColor,
                foregroundColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CampanhaSorteioFormScreen(lojaId: widget.lojaId),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Nova Campanha'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCampanhasTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .orderBy('criadaEm', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: _primaryColor),
                const SizedBox(height: 16),
                Text(
                  'Carregando campanhas...',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        var docs = snap.data!.docs;

        // Filtro por busca
        if (_busca.isNotEmpty) {
          final busca = _busca.toLowerCase();
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final nome = (data['nome'] ?? '').toString().toLowerCase();
            final desc = (data['descricao'] ?? '').toString().toLowerCase();
            return nome.contains(busca) || desc.contains(busca);
          }).toList();
        }

        // Filtro por status
        if (_filtroStatus != 'todas') {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final status = data['status'] ?? '';
            final ativa = data['ativa'] == true;
            if (_filtroStatus == 'ativas') return ativa && status != 'finalizada';
            if (_filtroStatus == 'pausadas') return status == 'pausada';
            if (_filtroStatus == 'finalizadas') return status == 'finalizada';
            return true;
          }).toList();
        }

        return RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 400));
            if (mounted) setState(() {});
          },
          color: _primaryColor,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _buscaController,
                        onChanged: (v) => setState(() => _busca = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou descrição...',
                          prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                          suffixIcon: _busca.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    _buscaController.clear();
                                    setState(() => _busca = '');
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
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('Todas', 'todas'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Ativas', 'ativas'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Pausadas', 'pausadas'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Finalizadas', 'finalizadas'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: docs.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  docs.isEmpty && _busca.isEmpty && _filtroStatus == 'todas'
                                      ? 'Nenhuma campanha criada'
                                      : 'Nenhuma campanha encontrada',
                                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _filtroStatus != 'todas' || _busca.isNotEmpty
                                      ? 'Tente outro filtro ou termo de busca.'
                                      : 'Crie sua primeira campanha de sorteio',
                                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                                  textAlign: TextAlign.center,
                                ),
                                if (_busca.isEmpty && _filtroStatus == 'todas') ...[
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CampanhaSorteioFormScreen(lojaId: widget.lojaId),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Criar Campanha'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final data = docs[i].data() as Map<String, dynamic>;
                            final id = docs[i].id;
                            return _buildCampanhaCard(id, data);
                          },
                          childCount: docs.length,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _filtroStatus == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filtroStatus = value),
      selectedColor: _primaryColor.withValues(alpha:0.3),
      checkmarkColor: _primaryColor,
    );
  }

  String _formatarData(dynamic ts) {
    if (ts == null) return '—';
    if (ts is DateTime) return DateFormat('dd/MM/yyyy').format(ts);
    if (ts is Timestamp) return DateFormat('dd/MM/yyyy').format(ts.toDate());
    return '—';
  }

  /// Diálogo com instruções para gravar a tela (Opção 1: abrir gravação do sistema).
  void _mostrarDialogGravarSorteio(
    BuildContext context, {
    required String lojaId,
    required String campanhaId,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.videocam, color: Color(0xFF22C55E)),
            SizedBox(width: 10),
            Text('Gravar tela do sorteio'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Para gravar o sorteio na tela do celular:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text('1. Toque em "Abrir configurações" para acessar as configurações do aparelho.'),
              SizedBox(height: 6),
              Text('2. Em muitos celulares, a gravação de tela fica na barra de notificações (arraste de cima para baixo) — procure por "Gravar tela" ou "Screen record".'),
              SizedBox(height: 6),
              Text('3. Toque em "Abrir Roleta" abaixo, inicie a gravação do sistema e depois gire a roleta.'),
              SizedBox(height: 12),
              Text(
                'Assim o vídeo mostra o sorteio real, sem parecer combinado.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          if (defaultTargetPlatform == TargetPlatform.android)
            TextButton.icon(
              onPressed: () async {
                try {
                  const AndroidIntent intent = AndroidIntent(
                    action: 'android.settings.SETTINGS',
                  );
                  await intent.launch();
                } catch (_) {}
                // Mantém o diálogo aberto para o usuário voltar e tocar em "Abrir Roleta"
              },
              icon: const Icon(Icons.settings, size: 20),
              label: const Text('Abrir configurações'),
            ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GloboSorteioScreen(
                    lojaId: lojaId,
                    campanhaId: campanhaId,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bubble_chart, size: 20),
            label: const Text('Abrir Roleta'),
            style: FilledButton.styleFrom(backgroundColor: _successColor),
          ),
        ],
      ),
    );
  }

  Widget _buildCampanhaCard(String id, Map<String, dynamic> data) {
    final nome = data['nome'] ?? 'Sem nome';
    final status = data['status'] ?? 'ativa';
    final descricao = data['descricao'] ?? '';
    final ativa = data['ativa'] == true;
    final dataInicio = data['dataInicio'];
    final dataFim = data['dataFim'];
    final dataSorteio = data['dataSorteio'];

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'finalizada':
        statusColor = Colors.grey;
        statusIcon = Icons.check_circle;
        break;
      case 'pausada':
        statusColor = _warningColor;
        statusIcon = Icons.pause_circle;
        break;
      default:
        statusColor = _successColor;
        statusIcon = Icons.play_circle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
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
                colors: [_primaryColor.withValues(alpha:0.1), _secondaryColor.withValues(alpha:0.05)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha:0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.campaign, color: _primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (descricao.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            descricao,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${_formatarData(dataInicio)} ? ${_formatarData(dataFim)} | Sorteio: ${_formatarData(dataSorteio)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Toggle Ativa/Inativa
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _toggleCampanhaAtiva(id, !ativa, nome),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: ativa
                            ? _successColor.withValues(alpha:0.1)
                            : Colors.grey.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: ativa ? _successColor : Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            ativa ? Icons.check_circle : Icons.cancel,
                            color: ativa ? _successColor : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ativa ? 'CAMPANHA ATIVA' : 'CAMPANHA INATIVA',
                            style: TextStyle(
                              color: ativa ? _successColor : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.toggle_on,
                            color: ativa ? _successColor : Colors.grey,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.edit,
                    label: 'Editar',
                    color: _primaryColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CampanhaSorteioFormScreen(
                            lojaId: widget.lojaId,
                            campanhaId: id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.bubble_chart,
                    label: 'Globo',
                    color: _secondaryColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GloboSorteioScreen(
                            lojaId: widget.lojaId,
                            campanhaId: id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.history,
                    label: 'Histórico',
                    color: _warningColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CampanhaSorteioHistoricoScreen(
                            lojaId: widget.lojaId,
                            campanhaId: id,
                            nomeCampanha: nome,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.delete_outline,
                    label: 'Excluir',
                    color: _errorColor,
                    onTap: () => _excluirCampanha(id, nome),
                  ),
                ),
              ],
            ),
          ),
          // Botão para gravar vídeo do sorteio (instruções + abrir configurações do sistema + Roleta)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              color: _successColor.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _mostrarDialogGravarSorteio(context, lojaId: widget.lojaId, campanhaId: id),
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam, color: _successColor, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Gravar Sorteio',
                        style: TextStyle(
                          color: _successColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

