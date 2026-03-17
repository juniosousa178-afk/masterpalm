// lib/screens/campanha_sorteio_historico_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/text_utils.dart';

class CampanhaSorteioHistoricoScreen extends StatefulWidget {
  final String lojaId;
  final String campanhaId;
  final String? nomeCampanha;

  const CampanhaSorteioHistoricoScreen({
    super.key,
    required this.lojaId,
    required this.campanhaId,
    this.nomeCampanha,
  });

  @override
  State<CampanhaSorteioHistoricoScreen> createState() =>
      _CampanhaSorteioHistoricoScreenState();
}

class _CampanhaSorteioHistoricoScreenState
    extends State<CampanhaSorteioHistoricoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text.toLowerCase()));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 4,
        shadowColor: Colors.greenAccent.withValues(alpha:0.3),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hist�rico',
              style: TextStyle(fontSize: 18),
            ),
            if (widget.nomeCampanha != null)
              Text(
                widget.nomeCampanha!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar lista',
            onPressed: () => _exportarLista(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(
              icon: Icon(Icons.people_outline, size: 20),
              text: 'Participantes',
            ),
            Tab(
              icon: Icon(Icons.emoji_events_outlined, size: 20),
              text: 'Vencedores',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Campo de busca
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou n�mero...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF10121A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.greenAccent),
                ),
              ),
            ),
          ),
          // Conte�do das tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildParticipantesTab(),
                _buildVencedoresTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tab de todos os participantes
  Widget _buildParticipantesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .doc(widget.campanhaId)
          .collection('participantes')
          .orderBy('dataParticipacao', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.greenAccent),
          );
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.people_outline,
            message: 'Nenhum participante cadastrado ainda.',
            subtitle: 'Os n�meros da sorte aparecer�o aqui quando\nvendas forem conclu�das.',
          );
        }

        final docs = snap.data!.docs;

        // Filtrar pela busca
        final filtered = docs.where((doc) {
          if (_searchQuery.isEmpty) return true;
          final data = doc.data() as Map<String, dynamic>;
          final nome = (data['clienteNome'] ?? '').toString().toLowerCase();
          final numero = (data['numeroSorte'] ?? '').toString().toLowerCase();
          return nome.contains(_searchQuery) || numero.contains(_searchQuery);
        }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(
            icon: Icons.search_off,
            message: 'Nenhum resultado encontrado.',
            subtitle: 'Tente buscar por outro termo.',
          );
        }

        return Column(
          children: [
            // Contador
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${filtered.length} participantes',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
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
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final data = filtered[i].data() as Map<String, dynamic>;
                  return _buildParticipanteCard(data);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Tab de vencedores (sorteios realizados)
  Widget _buildVencedoresTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .doc(widget.campanhaId)
          .collection('historico_sorteios')
          .orderBy('data', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.greenAccent),
          );
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.emoji_events_outlined,
            message: 'Nenhum sorteio realizado ainda.',
            subtitle: 'Use o Globo para realizar o sorteio\ne revelar os vencedores.',
          );
        }

        final docs = snap.data!.docs;

        // Filtrar pela busca
        final filtered = docs.where((doc) {
          if (_searchQuery.isEmpty) return true;
          final data = doc.data() as Map<String, dynamic>;
          final nome = (data['nomeCliente'] ?? '').toString().toLowerCase();
          final numero = (data['numero'] ?? '').toString().toLowerCase();
          return nome.contains(_searchQuery) || numero.contains(_searchQuery);
        }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(
            icon: Icons.search_off,
            message: 'Nenhum resultado encontrado.',
            subtitle: 'Tente buscar por outro termo.',
          );
        }

        return Column(
          children: [
            // Contador
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.emoji_events,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${filtered.length} vencedor${filtered.length > 1 ? "es" : ""}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Lista
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final data = filtered[i].data() as Map<String, dynamic>;
                  return _buildVencedorCard(data);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Card de participante
  Widget _buildParticipanteCard(Map<String, dynamic> data) {
    final numero = data['numeroSorte'] ?? '-----';
    final nome = data['clienteNome'] ?? 'Cliente n�o identificado';
    final telefone = data['clienteTelefone'] ?? '';
    final email = data['clienteEmail'] ?? '';
    final valorPedido = data['valorPedido'] as num?;
    final dataParticipacao = (data['dataParticipacao'] as Timestamp?)?.toDate();
    final sorteado = data['sorteado'] == true;

    return Card(
      color: const Color(0xFF10121A),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: sorteado
            ? const BorderSide(color: Colors.amber, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // N�mero e badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: sorteado
                          ? [Colors.amber.shade700, Colors.orange.shade700]
                          : [Colors.greenAccent.shade700, Colors.green.shade700],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    numero,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const Spacer(),
                if (sorteado)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emoji_events, color: Colors.amber, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'VENCEDOR',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Nome
            Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.white54, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nome,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Info adicional
            Row(
              children: [
                if (valorPedido != null) ...[
                  const Icon(Icons.attach_money, color: Colors.white38, size: 16),
                  Text(
                    'R\$ ${valorPedido.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                ],
                if (dataParticipacao != null) ...[
                  const Icon(Icons.calendar_today, color: Colors.white38, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${dataParticipacao.day.toString().padLeft(2, '0')}/${dataParticipacao.month.toString().padLeft(2, '0')}/${dataParticipacao.year}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ],
            ),
            // Bot�es de a��o
            if (telefone.isNotEmpty || email.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (telefone.isNotEmpty)
                    IconButton(
                      onPressed: () => _abrirWhatsApp(telefone, nome),
                      icon: const Icon(Icons.message, color: Color(0xFF25D366)),
                      tooltip: 'WhatsApp',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366).withValues(alpha:0.15),
                      ),
                    ),
                  if (telefone.isNotEmpty)
                    const SizedBox(width: 8),
                  if (telefone.isNotEmpty)
                    IconButton(
                      onPressed: () => _ligar(telefone),
                      icon: const Icon(Icons.phone, color: Colors.blue),
                      tooltip: 'Ligar',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.withValues(alpha:0.15),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Card de vencedor
  Widget _buildVencedorCard(Map<String, dynamic> data) {
    final numero = data['numero'] ?? '-----';
    final nome = data['nomeCliente'] ?? 'Cliente n�o identificado';
    final telefone = data['telefoneCliente'] ?? '';
    final valorPedido = data['valorPedido'] as num?;
    final dataSorteio = (data['data'] as Timestamp?)?.toDate();

    return Card(
      color: const Color(0xFF10121A),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.amber, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com trof�u
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade600, Colors.orange.shade600],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VENCEDOR',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // N�mero premiado
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.withValues(alpha:0.2),
                    Colors.orange.withValues(alpha:0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'N�MERO PREMIADO',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    numero,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Info adicional
            Row(
              children: [
                if (valorPedido != null) ...[
                  const Icon(Icons.attach_money, color: Colors.white38, size: 16),
                  Text(
                    'R\$ ${valorPedido.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                ],
                if (dataSorteio != null) ...[
                  const Icon(Icons.calendar_today, color: Colors.white38, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${dataSorteio.day.toString().padLeft(2, '0')}/${dataSorteio.month.toString().padLeft(2, '0')}/${dataSorteio.year} �s ${dataSorteio.hour.toString().padLeft(2, '0')}:${dataSorteio.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ],
            ),
            // Bot�o WhatsApp
            if (telefone.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _abrirWhatsAppVencedor(telefone, nome, numero),
                  icon: const Icon(Icons.message, color: Colors.white),
                  label: const Text(
                    'Enviar Parab�ns via WhatsApp',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Estado vazio
  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportarLista() async {
    try {
      final isParticipantes = _tabController.index == 0;
      final snap = isParticipantes
          ? await FirebaseFirestore.instance
              .collection('lojas')
              .doc(widget.lojaId)
              .collection('campanhas_sorteio')
              .doc(widget.campanhaId)
              .collection('participantes')
              .orderBy('dataParticipacao', descending: true)
              .limit(500)
              .get()
          : await FirebaseFirestore.instance
              .collection('lojas')
              .doc(widget.lojaId)
              .collection('campanhas_sorteio')
              .doc(widget.campanhaId)
              .collection('historico_sorteios')
              .orderBy('data', descending: true)
              .limit(500)
              .get();

      final docs = snap.docs;
      if (docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum dado para exportar.')),
        );
        return;
      }

      final buffer = StringBuffer();
      if (isParticipantes) {
        buffer.writeln('N�mero;Nome;Telefone;Email;Valor;Data');
        for (final doc in docs) {
          final d = doc.data();
          final ts = d['dataParticipacao'] as Timestamp?;
          buffer.writeln(
            '${d['numeroSorte'] ?? ''};'
            '${(d['clienteNome'] ?? '').toString().replaceAll(';', ',')};'
            '${d['clienteTelefone'] ?? ''};'
            '${d['clienteEmail'] ?? ''};'
            '${(d['valorPedido'] as num?)?.toStringAsFixed(2) ?? ''};'
            '${ts != null ? '${ts.toDate().day.toString().padLeft(2, '0')}/${ts.toDate().month.toString().padLeft(2, '0')}/${ts.toDate().year}' : ''}',
          );
        }
      } else {
        buffer.writeln('N�mero;Nome;Telefone;Valor;Data Sorteio');
        for (final doc in docs) {
          final d = doc.data();
          final ts = d['data'] as Timestamp?;
          buffer.writeln(
            '${d['numero'] ?? ''};'
            '${(d['nomeCliente'] ?? '').toString().replaceAll(';', ',')};'
            '${d['telefoneCliente'] ?? ''};'
            '${(d['valorPedido'] as num?)?.toStringAsFixed(2) ?? ''};'
            '${ts != null ? '${ts.toDate().day.toString().padLeft(2, '0')}/${ts.toDate().month.toString().padLeft(2, '0')}/${ts.toDate().year}' : ''}',
          );
        }
      }

      final nomeArquivo = isParticipantes ? 'participantes' : 'vencedores';
      await SharePlus.instance.share(
        ShareParams(
          text: sanitizeForPlatform(buffer.toString()),
          subject: sanitizeForPlatform('${widget.nomeCampanha ?? 'Campanha'} - $nomeArquivo'),
        ),
      );
    } catch (e) {
      debugPrint('Erro ao exportar (type=${e.runtimeType})');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar: $e')),
      );
    }
  }

  /// Abre WhatsApp
  Future<void> _abrirWhatsApp(String telefone, String nome) async {
    String telefoneLimpo = telefone.replaceAll(RegExp(r'[^\d]'), '');
    if (!telefoneLimpo.startsWith('55') && telefoneLimpo.length <= 11) {
      telefoneLimpo = '55$telefoneLimpo';
    }

    final url = 'https://wa.me/$telefoneLimpo';
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp (type=${e.runtimeType})');
    }
  }

  /// Abre WhatsApp com mensagem de parab�ns
  Future<void> _abrirWhatsAppVencedor(
    String telefone,
    String nome,
    String numero,
  ) async {
    String telefoneLimpo = telefone.replaceAll(RegExp(r'[^\d]'), '');
    if (!telefoneLimpo.startsWith('55') && telefoneLimpo.length <= 11) {
      telefoneLimpo = '55$telefoneLimpo';
    }

    final mensagem = '''
?? *PARAB�NS, ${nome.split(' ').first}!* ??

Voc� foi o GRANDE VENCEDOR do nosso sorteio!

?? *N�mero premiado:* $numero

Entre em contato conosco para retirar seu pr�mio!

?? Obrigado por participar!
''';

    final url =
        'https://wa.me/$telefoneLimpo?text=${Uri.encodeComponent(mensagem)}';
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp (type=${e.runtimeType})');
    }
  }

  /// Liga para o telefone
  Future<void> _ligar(String telefone) async {
    String telefoneLimpo = telefone.replaceAll(RegExp(r'[^\d]'), '');
    final url = 'tel:$telefoneLimpo';
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Erro ao ligar (type=${e.runtimeType})');
    }
  }
}

