import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/cliente_auth_service.dart';

/// Tela de Perfil do Cliente (usando novo sistema de autenticação)
class PerfilClienteScreenNovo extends StatefulWidget {
  final String lojaId;
  final String clienteId;

  const PerfilClienteScreenNovo({
    super.key,
    required this.lojaId,
    required this.clienteId,
  });

  @override
  State<PerfilClienteScreenNovo> createState() => _PerfilClienteScreenNovoState();
}

class _PerfilClienteScreenNovoState extends State<PerfilClienteScreenNovo> {
  Future<Map<String, dynamic>?> _carregarDadosPerfil() async {
    final session = await ClienteAuthService.getClienteLogado();
    if (session == null) return null;
    final email = (session['email'] ?• '').toString().trim().toLowerCase();
    if (email.isEmpty) return null;
    final sessionClienteId = session['clienteId']?.toString();
    if (sessionClienteId != widget.clienteId) return null;
    return ClienteAuthService.getDadosCompletos(
      lojaId: widget.lojaId,
      clienteId: widget.clienteId,
      email: email,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        centerTitle: true,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _carregarDadosPerfil(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final dados = snapshot.data;
          if (dados == null || dados.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Não foi possível carregar seu perfil',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pode ser problema de conexão ou sessão expirada. '
                      'Tente novamente ou faça login no catálogo correto.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('Tentar novamente'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ClienteAuthService.logout();
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Sair e fazer login novamente'),
                    ),
                  ],
                ),
              ),
            );
          }
          final nome = dados['nome'] ?• 'Sem nome';
          final email = dados['email'] ?• '';
          final lojaId = widget.lojaId;
          final clienteId = widget.clienteId;
          final telefone = dados['telefone'] ?• '';
          final cuponsDoc = List<Map<String, dynamic>>.from(dados['cupons'] ?• []);
          final pedidosClienteDoc = List<Map<String, dynamic>>.from(dados['pedidos'] ?• []);
          final favoritosIds = List<String>.from((dados['favoritos'] ?• []).map((e) => e.toString()))
              .where((id) => id.isNotEmpty)
              .toList();

          return FutureBuilder<Map<String, dynamic>>(
            future: _buscarDadosPerfilCompletos(
              lojaId: lojaId,
              email: email,
              clienteId: clienteId,
              pedidosClienteDoc: pedidosClienteDoc,
              favoritosIds: favoritosIds,
            ),
            builder: (context, snapshotDados) {
              final pedidos = snapshotDados.data?['pedidos'] as List<Map<String, dynamic>>• ?• [];
              final pedidosPrecisaReconectar =
                  snapshotDados.data?['pedidosPrecisaReconectar'] as bool• ?• false;
              final cuponsRoleta = snapshotDados.data?['cuponsRoleta'] as List<Map<String, dynamic>>• ?• [];
              final numerosCampanhas = snapshotDados.data?['numerosCampanhas'] as List<Map<String, dynamic>>• ?• [];
              final cupons = _mesclarCupons(cuponsDoc, cuponsRoleta);
              final todosNumerosSorte = _mesclarNumerosSorte(pedidosClienteDoc, numerosCampanhas);
              final favoritosProdutos = snapshotDados.data?['favoritosProdutos'] as List<Map<String, dynamic>>• ?• [];

              return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabeçalho com foto e nome
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue,
                  child: Text(
                    nome.isNotEmpty • nome[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  nome,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                if (telefone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    telefone,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),

                // Botão Editar Dados
                OutlinedButton.icon(
                  onPressed: () => _mostrarDialogEditarDados(context, dados),
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar Dados Pessoais'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),

                // Botão Alterar Senha
                OutlinedButton.icon(
                  onPressed: () => _mostrarDialogAlterarSenha(context),
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Alterar Senha'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 32),

                // Seção de Cupons (doc clientes + roleta clientes_catalogo)
                _buildSecao(
                  context,
                  'Meus Cupons',
                  Icons.local_offer,
                  Colors.orange,
                  cupons.isEmpty
                      • const Text('Você ainda não tem cupons de desconto')
                      : Column(
                          children: cupons.map((cupom) {
                            final codigo = cupom['codigo'] ?• '';
                            final desconto = (cupom['desconto'] as num?)?.toDouble() ?• 0.0;
                            final tipo = (cupom['tipo'] ?• cupom['origem'] ?• '').toString();
                            final validade = cupom['validade']?.toString() ??
                                (cupom['dataExpiracao'] != null
                                    • _formatarData(cupom['dataExpiracao'])
                                    : '');
                            final usado = cupom['usado'] ?• false;
                            final isFreteGratis = tipo == 'frete_gratis';
                            final descricao = isFreteGratis
                                • 'Frete grátis'
                                : '${desconto.toStringAsFixed(0)}% de desconto';

                            return Card(
                              color: usado • Colors.grey[300] : Colors.orange[50],
                              child: ListTile(
                                leading: Icon(
                                  usado • Icons.check_circle : Icons.local_offer,
                                  color: usado • Colors.grey : Colors.orange,
                                ),
                                title: Text(
                                  codigo,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: usado
                                        • TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: Text('$descricao${validade.isNotEmpty • '\nVálido até $validade' : ''}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!usado && codigo.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 22),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: codigo));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: const Row(
                                                children: [
                                                  Icon(Icons.check, color: Colors.white, size: 20),
                                                  SizedBox(width: 12),
                                                  Text('Cupom copiado!'),
                                                ],
                                              ),
                                              backgroundColor: Colors.green,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          );
                                        },
                                        tooltip: 'Copiar cupom',
                                        style: IconButton.styleFrom(
                                          padding: const EdgeInsets.all(4),
                                          minimumSize: const Size(36, 36),
                                        ),
                                      ),
                                    Text(
                                      usado • 'USADO' : 'ATIVO',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: usado • Colors.grey[600] : Colors.orange[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),

                // Seção de Números da Sorte (doc cliente + campanhas_sorteio)
                _buildSecao(
                  context,
                  'Números da Sorte',
                  Icons.casino,
                  Colors.green,
                  todosNumerosSorte.isEmpty
                      • const Text('Você ainda não tem números da sorte')
                      : Column(
                          children: todosNumerosSorte.map((item) {
                            final numeroSorte = item['numeroSorte'] ?• '';
                            final data = item['data'] ?• '';
                            final valor = (item['valor'] as num?)?.toDouble() ?• 0.0;
                            final campanha = item['campanhaNome']?.toString();

                            return Card(
                              color: Colors.green[50],
                              child: ListTile(
                                leading: const Icon(Icons.casino, color: Colors.green),
                                title: Text(
                                  'Número: $numeroSorte',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  campanha != null && campanha.isNotEmpty
                                      • '$campanha\n$data • R\$ ${valor.toStringAsFixed(2)}'
                                      : 'Pedido de $data\nR\$ ${valor.toStringAsFixed(2)}',
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 24),

                // Seção Meus Favoritos
                _buildSecao(
                  context,
                  'Meus Favoritos',
                  Icons.favorite,
                  Colors.pink,
                  favoritosProdutos.isEmpty
                      • const Text('Você ainda não tem produtos favoritos')
                      : _buildFavoritosGrid(context, favoritosProdutos, lojaId, clienteId, email),
                ),
                const SizedBox(height: 24),

                // Seção de Meus Pedidos (de pre_pedidos - status real)
                _buildSecao(
                  context,
                  'Meus Pedidos',
                  Icons.shopping_bag,
                  Colors.blue,
                  snapshotDados.connectionState == ConnectionState.waiting
                      • const Center(child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ))
                      : pedidos.isEmpty
                          • _buildMensagemMeusPedidosVazio(
                              context,
                              pedidosPrecisaReconectar,
                            )
                          : Column(
                              children: pedidos.map((pedido) {
                                final id = (pedido['id'] ?• '').toString();
                                final status = (pedido['status'] ?• 'pendente').toString();
                                final total = (pedido['total'] as num?)?.toDouble() ?• 0.0;
                                final dataCriacao = pedido['dataCriacao'];
                                String dataStr = pedido['dataStr']?.toString() ?• '';
                                if (dataStr.isEmpty && dataCriacao != null) {
                                  try {
                                    final dt = (dataCriacao as dynamic).toDate() as DateTime;
                                    dataStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                                  } catch (e) {
                                    if (kDebugMode) {
                                      debugPrint('perfil_cliente: erro ao formatar dataCriacao (type=${e.runtimeType})');
                                    }
                                  }
                                }

                                final statusLabel = _statusLabel(status);
                                final statusColor = _statusColor(status);
                                final codigoRastreio = (pedido['codigoRastreio'] ?• pedido['codigo_rastreio'] ?• pedido['rastreio'] ?• '').toString().trim();

                                return Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.shopping_bag, color: Colors.blue),
                                    title: Text(
                                      'Pedido #${id.length > 8 • id.substring(0, 8) : id}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${dataStr.isNotEmpty • '$dataStr\n' : ''}R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                                        ),
                                        if (codigoRastreio.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: OutlinedButton.icon(
                                              onPressed: () async {
                                                // Link direto para rastreio (Correios e transportadoras)
                                                final url = 'https://www.linkcorreios.com.br/?cc=${Uri.encodeComponent(codigoRastreio)}';
                                                final uri = Uri.parse(url);
                                                if (await canLaunchUrl(uri)) {
                                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                                }
                                              },
                                              icon: const Icon(Icons.local_shipping, size: 16),
                                              label: Text('Rastrear: $codigoRastreio', style: const TextStyle(fontSize: 12)),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Chip(
                                      label: Text(
                                        statusLabel,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      backgroundColor: statusColor.withValues(alpha:0.2),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                ),
                const SizedBox(height: 32),

                // Botão Sair
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirma = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sair'),
                        content: const Text('Deseja realmente sair da sua conta?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sair'),
                          ),
                        ],
                      ),
                    );

                    if (confirma == true) {
                      await ClienteAuthService.logout();
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Você saiu da sua conta'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair da Conta'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          );
            },
          );
        },
      ),
    );
  }

  /// Busca todos os dados do perfil: pedidos, cupons roleta, números campanhas, favoritos
  static Future<Map<String, dynamic>> _buscarDadosPerfilCompletos({
    required String lojaId,
    required String email,
    required String clienteId,
    required List<Map<String, dynamic>> pedidosClienteDoc,
    required List<String> favoritosIds,
  }) async {
    final pedidosResult = await _buscarPedidosCompletos(
      lojaId,
      email,
      pedidosClienteDoc,
      clienteId,
    );
    final cuponsRoleta = await ClienteAuthService.getCuponsRoleta(
      lojaId: lojaId,
      email: email,
    );
    final numerosCampanhas = await ClienteAuthService.getNumerosSorteCampanhas(
      lojaId: lojaId,
      clienteId: clienteId,
      email: email,
    );
    final favoritosProdutos = await _buscarProdutosPorIds(lojaId, favoritosIds);
    return {
      'pedidos': pedidosResult.pedidos,
      'pedidosPrecisaReconectar': pedidosResult.precisaReconectar,
      'cuponsRoleta': cuponsRoleta,
      'numerosCampanhas': numerosCampanhas,
      'favoritosProdutos': favoritosProdutos,
    };
  }

  /// Busca produtos por IDs (Firestore: lojas/{lojaId}/produtos)
  static Future<List<Map<String, dynamic>>> _buscarProdutosPorIds(
    String lojaId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    try {
      final ref = FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos');
      final results = <Map<String, dynamic>>[];
      // Firestore whereIn limita 10 por query
      for (var i = 0; i < ids.length; i += 10) {
        final batch = ids.skip(i).take(10).toList();
        if (batch.isEmpty) break;
        final snap = await ref
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          d['id'] = doc.id;
          results.add(d);
        }
      }
      // manter ordem original dos favoritos
      final byId = {for (final p in results) p['id'] as String: p};
      return ids.map((id) => byId[id]).whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      return [];
    }
  }

  Widget _buildFavoritosGrid(BuildContext context, List<Map<String, dynamic>> produtos, String lojaId, String clienteId, String email) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: produtos.map((p) {
        final id = (p['id'] ?• '').toString();
        final nome = (p['nome'] ?• '').toString();
        final preco = (p['preco'] ?• p['valor'] ?• 0.0) is num
            • ((p['preco'] ?• p['valor']) as num).toDouble()
            : 0.0;
        final imagens = (p['imagens'] as List?)?.cast<String>() ?• [];
        final imageUrl = imagens.isNotEmpty • imagens.first : (p['imageUrl'] ?• p['url_foto'] ?• '').toString();
        return SizedBox(
          width: 120,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (imageUrl.isNotEmpty)
                    AspectRatio(
                      aspectRatio: 1,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                      ),
                    )
                  else
                    const AspectRatio(
                      aspectRatio: 1,
                      child: Icon(Icons.image),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'R\$ ${preco.toStringAsFixed(2).replaceAll('.', ',')}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green[700]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.white.withValues(alpha:0.9),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () async {
                        await ClienteAuthService.toggleFavorito(
                          lojaId: lojaId,
                          clienteId: clienteId,
                          email: email,
                          productId: id,
                        );
                        // StreamBuilder reage automaticamente à alteração no Firestore
                      },
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.favorite, color: Colors.pink, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Mescla cupons do doc clientes com cupons da roleta (clientes_catalogo)
  static List<Map<String, dynamic>> _mesclarCupons(
    List<Map<String, dynamic>> doc,
    List<Map<String, dynamic>> roleta,
  ) {
    final codigosVistos = <String>{};
    final resultado = <Map<String, dynamic>>[];
    for (final c in doc) {
      final cod = (c['codigo'] ?• '').toString();
      if (cod.isNotEmpty && !codigosVistos.contains(cod)) {
        codigosVistos.add(cod);
        resultado.add(c);
      }
    }
    for (final c in roleta) {
      final cod = (c['codigo'] ?• '').toString();
      if (cod.isNotEmpty && !codigosVistos.contains(cod)) {
        codigosVistos.add(cod);
        resultado.add(c);
      }
    }
    return resultado;
  }

  /// Mescla números da sorte do doc cliente com participações em campanhas
  static List<Map<String, dynamic>> _mesclarNumerosSorte(
    List<Map<String, dynamic>> pedidosDoc,
    List<Map<String, dynamic>> campanhas,
  ) {
    final numerosDoc = pedidosDoc
        .where((p) => (p['numeroSorte'] ?• '').toString().isNotEmpty)
        .map((p) => {
              'numeroSorte': p['numeroSorte'],
              'data': p['data'] ?• '',
              'valor': (p['valor'] as num?)?.toDouble() ?• 0.0,
              'campanhaNome': null,
            })
        .toList();
    return [...numerosDoc, ...campanhas]
      ..sort((a, b) => (b['data'] ?• '').compareTo(a['data'] ?• ''));
  }

  /// Busca pedidos de clientes_portal + doc cliente (MP) e mescla ordenados por data
  static Future<({List<Map<String, dynamic>> pedidos, bool precisaReconectar})>
      _buscarPedidosCompletos(
    String lojaId,
    String email,
    List<Map<String, dynamic>> pedidosClienteDoc,
    String clienteId,
  ) async {
    final result = await ClienteAuthService.getPedidosDoCliente(
      lojaId: lojaId,
      email: email,
      clienteId: clienteId,
    );
    final fromPortal = result.pedidos;
    final idsPrePedidos = fromPortal.map((p) => p['id']?.toString()).toSet();

    // Pedidos do doc (gerarCupomNumeroSorte) que não estão em pre_pedidos = MP
    final onlyFromDoc = pedidosClienteDoc
        .where((p) => !idsPrePedidos.contains(p['id']?.toString()))
        .map((p) => {
              'id': p['id'],
              'status': p['status'] ?• 'Confirmado',
              'total': (p['valor'] as num?)?.toDouble() ?• 0.0,
              'dataCriacao': null,
              'dataStr': p['data'] ?• '',
            })
        .toList();

    final todos = [...fromPortal, ...onlyFromDoc];
    todos.sort((a, b) {
      final dtA = a['dataCriacao'] != null
          • (a['dataCriacao'] as dynamic).toDate() as DateTime?
          : null;
      final dtB = b['dataCriacao'] != null
          • (b['dataCriacao'] as dynamic).toDate() as DateTime?
          : null;
      if (dtA != null && dtB != null)       return dtB.compareTo(dtA);
      if (dtA != null) return -1;
      if (dtB != null) return 1;
      return 0; // mantém ordem quando ambos sem dataCriacao
    });
    return (pedidos: todos, precisaReconectar: result.precisaReconectar);
  }

  static String _formatarData(dynamic timestamp) {
    try {
      final dt = (timestamp as dynamic).toDate() as DateTime;
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  static String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pendente': return 'Pendente';
      case 'confirmado': return 'Confirmado';
      case 'embalando': return 'Embalando';
      case 'enviado': return 'Enviado';
      case 'entregue': return 'Entregue';
      case 'cancelado': return 'Cancelado';
      default: return status;
    }
  }

  static Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pendente': return Colors.orange;
      case 'confirmado': return Colors.green;
      case 'embalando': return Colors.blue;
      case 'enviado': return Colors.blue.shade700;
      case 'entregue': return Colors.green.shade700;
      case 'cancelado': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildMensagemMeusPedidosVazio(
    BuildContext context,
    bool precisaReconectar,
  ) {
    if (precisaReconectar) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nenhum pedido carregado. Saia e entre novamente na sua conta para sincronizar.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await ClienteAuthService.logout();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sair e entrar novamente'),
            ),
          ],
        ),
      );
    }
    return Text(
      'Você ainda não fez pedidos',
      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
    );
  }

  Widget _buildSecao(BuildContext context, String titulo, IconData icone, Color cor, Widget conteudo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icone, color: cor),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        conteudo,
      ],
    );
  }

  /// Dialog para editar dados pessoais
  void _mostrarDialogEditarDados(BuildContext context, Map<String, dynamic> dadosAtuais) {
    final nomeController = TextEditingController(text: dadosAtuais['nome'] ?• '');
    final emailController = TextEditingController(text: dadosAtuais['email'] ?• '');
    final telefoneController = TextEditingController(text: dadosAtuais['telefone'] ?• '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Dados Pessoais'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nomeController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome Completo',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Digite seu nome';
                    }
                    if (value.length < 3) {
                      return 'Nome muito curto';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Digite seu email';
                    }
                    if (!value.contains('@')) {
                      return 'Email inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: telefoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                    hintText: '(00) 00000-0000',
                    helperText: 'Ex: 5533999999999',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              // Salvar alterações
              final resultado = await ClienteAuthService.atualizarDados(
                lojaId: widget.lojaId,
                clienteId: widget.clienteId,
                nome: nomeController.text.trim(),
                email: emailController.text.trim(),
                telefone: telefoneController.text.trim(),
              );

              if (!context.mounted) return;

              Navigator.pop(context);

              if (resultado['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dados atualizados com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(resultado['error'] ?• 'Erro ao atualizar dados'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  /// Dialog para alterar senha
  void _mostrarDialogAlterarSenha(BuildContext context) {
    final senhaAtualController = TextEditingController();
    final novaSenhaController = TextEditingController();
    final confirmarSenhaController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool mostrarSenhaAtual = false;
    bool mostrarNovaSenha = false;
    bool mostrarConfirmarSenha = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Alterar Senha'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: senhaAtualController,
                    obscureText: !mostrarSenhaAtual,
                    decoration: InputDecoration(
                      labelText: 'Senha Atual',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          mostrarSenhaAtual • Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => mostrarSenhaAtual = !mostrarSenhaAtual);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Digite sua senha atual';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: novaSenhaController,
                    obscureText: !mostrarNovaSenha,
                    decoration: InputDecoration(
                      labelText: 'Nova Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          mostrarNovaSenha • Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => mostrarNovaSenha = !mostrarNovaSenha);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Digite a nova senha';
                      }
                      if (value.length < 6) {
                        return 'Senha deve ter pelo menos 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmarSenhaController,
                    obscureText: !mostrarConfirmarSenha,
                    decoration: InputDecoration(
                      labelText: 'Confirmar Nova Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          mostrarConfirmarSenha • Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => mostrarConfirmarSenha = !mostrarConfirmarSenha);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Confirme a nova senha';
                      }
                      if (value != novaSenhaController.text) {
                        return 'As senhas não conferem';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                // Alterar senha
                final resultado = await ClienteAuthService.alterarSenha(
                  lojaId: widget.lojaId,
                  clienteId: widget.clienteId,
                  senhaAtual: senhaAtualController.text,
                  novaSenha: novaSenhaController.text,
                );

                if (!context.mounted) return;

                Navigator.pop(context);

                if (resultado['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Senha alterada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(resultado['error'] ?• 'Erro ao alterar senha'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Alterar'),
            ),
          ],
        ),
      ),
    );
  }
}

