// lib/screens/pedido_publico_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../core/logger.dart';
import '../repositories/pedido_status_publico_repository.dart';

/// Tela pública para visualizar o status do pedido
/// Acessível via: https://app.mastepalm.com.br/pedido/{prePedidoId}
class PedidoPublicoScreen extends StatefulWidget {
  final String lojaId;
  final String prePedidoId;

  const PedidoPublicoScreen({
    super.key,
    required this.lojaId,
    required this.prePedidoId,
  });

  @override
  State<PedidoPublicoScreen> createState() => _PedidoPublicoScreenState();
}

class _PedidoPublicoScreenState extends State<PedidoPublicoScreen> {
  final PedidoStatusPublicoRepository _pedidoStatusPublicoRepository =
      PedidoStatusPublicoRepository();
  bool _carregando = true;
  Map<String, dynamic>? _prePedido;
  bool _usandoFallbackLegado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarPedido();
  }

  Future<void> _carregarPedido() async {
    try {
      // ETAPA 9: usa APENAS pedido_status_publico (leitura pública). Sem fallback para pre_pedidos.
      final pedidoPublico =
          await _pedidoStatusPublicoRepository.getMapByPedidoId(
        lojaId: widget.lojaId,
        pedidoId: widget.prePedidoId,
      );

      if (pedidoPublico != null) {
        logD('[ETAPA9] PedidoPublicoScreen: carregou de pedido_status_publico');
        setState(() {
          _prePedido = _normalizarPedidoParaTela(pedidoPublico);
          _usandoFallbackLegado = false;
          _carregando = false;
        });
        return;
      }

      setState(() {
        _erro =
            'Pedido não encontrado ou ainda não disponível. '
            'Se você acabou de fazer o pedido, aguarde alguns instantes. '
            'Caso contrário, verifique o link ou entre em contato com a loja.';
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar pedido: $e';
        _carregando = false;
      });
    }
  }

  String _formatarValor(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatarData(dynamic timestamp) {
    if (timestamp == null) return '-';

    DateTime data;
    if (timestamp is Timestamp) {
      data = timestamp.toDate();
    } else if (timestamp is DateTime) {
      data = timestamp;
    } else {
      return '-';
    }

    return DateFormat('dd/MM/yyyy HH:mm').format(data);
  }

  Color _corStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return Colors.orange;
      case 'confirmado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _labelStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return 'Aguardando Confirmação';
      case 'confirmado':
        return 'Confirmado';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  IconData _iconeStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return Icons.schedule;
      case 'confirmado':
        return Icons.check_circle;
      case 'cancelado':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  void _copiarPedidoId() {
    Clipboard.setData(ClipboardData(text: widget.prePedidoId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ID do pedido copiado!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ❌ FUNÇÃO DESABILITADA: Cliente NÃO pode cancelar pedidos
  // Apenas ADMIN/VENDEDOR pode confirmar ou cancelar
  /*
  Future<void> _cancelarPedido() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Pedido'),
        content: const Text('Tem certeza que deseja cancelar este pedido?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sim', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _processando = true);

    try {
      // DELETAR o pedido ao invés de só mudar status
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('pre_pedidos')
          .doc(widget.prePedidoId)
          .delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido cancelado com sucesso!')),
      );

      // Voltar para tela anterior
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cancelar pedido: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processando = false);
      }
    }
  }

  Future<void> _confirmarPedido() async {
    if (_produtos == null || _clientes == null || _vendas == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aguarde, carregando dados...')),
      );
      return;
    }

    setState(() => _processando = true);

    try {
      final pedido = _prePedido!;
      final itens = (pedido['itens'] as List?) ?? [];
      final cliente = pedido['cliente'] as Map<String, dynamic>?;
      final frete = pedido['frete'] as Map<String, dynamic>?;

      // Criar itens de venda e baixar estoque
      final itensVenda = <VendaItem>[];
      for (final item in itens) {
        final nome = (item['nome'] ?? '').toString();
        final slug = (item['slug'] ?? '').toString();
        final qtd = (item['quantidade'] as num?)?.toInt() ?? 1;
        final preco = (item['precoUnitario'] as num?)?.toDouble() ?? 0.0;
        final tamanho = (item['tamanho'] ?? '').toString().trim();
        final cor = (item['cor'] ?? '').toString().trim();

        // Buscar produto no Hive primeiro
        var produto = slug.isNotEmpty
            ? VendasService.encontrarProdutoNoEstoque(
                produtosBox: _produtos!,
                slug: slug,
                lojaId: widget.lojaId,
              )
            : null;

        // Se não encontrou por slug, tenta por nome
        if (produto == null) {
          produto = VendasService.encontrarProdutoNoEstoque(
            produtosBox: _produtos!,
            nome: nome,
            lojaId: widget.lojaId,
          );
        }

        // Se não encontrou no Hive, buscar no Firestore e sincronizar
        if (produto == null) {
          debugPrint('⚠️ Produto não encontrado no Hive, buscando no Firestore: $nome (slug: $slug)');

          // Buscar todos os produtos no Firestore
          final QuerySnapshot produtosSnapshot = await FirebaseFirestore.instance
              .collection('lojas')
              .doc(widget.lojaId)
              .collection('produtos')
              .get();

          debugPrint('📦 Produtos encontrados no Firestore: ${produtosSnapshot.docs.length}');

          // Procurar produto por slug ou nome
          DocumentSnapshot? produtoDoc;
          for (final doc in produtosSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final docSlug = (data['slug'] ?? '').toString().trim().toLowerCase();
            final docNome = (data['nome'] ?? '').toString().trim().toLowerCase();

            if ((slug.isNotEmpty && docSlug == slug.trim().toLowerCase()) ||
                (nome.isNotEmpty && docNome == nome.trim().toLowerCase())) {
              produtoDoc = doc;
              debugPrint('✅ Produto encontrado no Firestore: ${doc.id}');
              break;
            }
          }

          if (produtoDoc == null) {
            throw Exception('Produto não encontrado no estoque: $nome. Verifique se o produto existe no cadastro.');
          }

          // Sincronizar produto do Firestore para o Hive
          final produtoData = produtoDoc.data() as Map<String, dynamic>;
          produto = Produto(
            idFirebase: produtoDoc.id,
            nome: produtoData['nome'] ?? '',
            custoReal: 0.0,
            frete: 0.0,
            gastosFixos: 0.0,
            gastosVariaveis: 0.0,
            precoSugerido: (produtoData['preco'] as num?)?.toDouble() ?? 0.0,
            precoFinal: (produtoData['preco'] as num?)?.toDouble() ?? 0.0,
            precoUnitario: (produtoData['preco'] as num?)?.toDouble() ?? 0.0,
            quantidade: (produtoData['quantidade'] as num?)?.toInt() ?? 0,
            categoria: produtoData['categoria'] ?? '',
            dataEntrada: DateTime.now(),
            slug: produtoData['slug'] ?? '',
            lojaId: widget.lojaId,
            descricao: produtoData['descricao'] ?? '',
            imagens: (produtoData['imagens'] as List?)?.cast<String>() ?? [],
          );

          // Salvar no Hive para próximas consultas
          await _produtos!.put(produto.idFirebase, produto);
          debugPrint('💾 Produto sincronizado do Firestore para Hive: ${produto.nome}');
        }

        // Estoque será baixado via transação Firestore em registrarVendaMulti
        debugPrint('📦 Produto encontrado: ${produto.nome} (estoque: ${produto.quantidade}, solicitado: $qtd)');

        itensVenda.add(VendaItem(
          produtoNome: nome,
          quantidade: qtd,
          tamanho: tamanho,
          cor: cor,
          precoUnitario: preco,
          lojaId: widget.lojaId,
          productId: produto.idFirebase.trim().isNotEmpty ? produto.idFirebase : null,
        ));
      }

      // Calcular valores
      final subtotal = (pedido['subtotal'] as num?)?.toDouble() ?? 0.0;
      final freteValor = (frete?['valor'] as num?)?.toDouble() ?? 0.0;
      final total = (pedido['total'] as num?)?.toDouble() ?? 0.0;

      // Determinar método de pagamento
      final pagamento = (pedido['pagamento'] ?? '').toString().toLowerCase();
      double dinheiro = 0, pix = 0, cartao = 0;

      switch (pagamento) {
        case 'pix':
          pix = total;
          break;
        case 'cartao':
        case 'cartão':
        case 'mercado pago':
          cartao = total;
          break;
        default:
          dinheiro = total;
      }

      // Registrar venda (salva no Hive, histórico do cliente e sincroniza com Firestore automaticamente)
      debugPrint('');
      debugPrint('═══════════════════════════════════════');
      debugPrint('📝 INICIANDO REGISTRO DE VENDA');
      debugPrint('═══════════════════════════════════════');
      debugPrint('🏪 Loja: ${widget.lojaId}');
      debugPrint('👤 Cliente: ${cliente?['nome']}');
      debugPrint('📦 Itens: ${itensVenda.length}');
      for (final item in itensVenda) {
        debugPrint('   - ${item.quantidade}x ${item.produtoNome} @ R\$ ${item.precoUnitario}');
      }
      debugPrint('💰 Total: R\$ $total');
      debugPrint('💳 Pagamento: ${pagamento.toUpperCase()}');
      debugPrint('═══════════════════════════════════════');

      final vendaRegistrada = await VendasService.registrarVendaMulti(
        produtosBox: _produtos!,
        clientesBox: _clientes!,
        vendasBox: _vendas!,
        clienteNome: cliente?['nome'] ?? 'Cliente',
        itens: itensVenda,
        dinheiro: dinheiro,
        pix: pix,
        cartao: cartao,
        vendedor: "Loja online",
        frete: freteValor,
        descontoPct: 0,
        observacao: pedido['observacao'] ?? '',
        lojaId: widget.lojaId,
      );

      debugPrint('');
      debugPrint('═══════════════════════════════════════');
      debugPrint('✅ VENDA REGISTRADA COM SUCESSO!');
      debugPrint('═══════════════════════════════════════');
      debugPrint('🆔 ID da venda: ${vendaRegistrada.key}');
      debugPrint('💰 Total: R\$ ${vendaRegistrada.total}');
      debugPrint('📅 Data: ${vendaRegistrada.data}');
      debugPrint('═══════════════════════════════════════');

      // Registrar participação em campanha de sorteio (se houver campanha ativa)
      Map<String, dynamic> campanhaResult = {
        'temCampanha': false,
        'numeros': <String>[],
        'campanhas': <Map<String, dynamic>>[],
      };

      try {
        campanhaResult = await CampanhasSorteioService.registrarParticipacao(
          lojaId: widget.lojaId,
          clienteNome: cliente?['nome'] ?? 'Cliente',
          clienteId: cliente?['id'],
          valorCompra: total,
          dataCompra: DateTime.now(),
          clienteEmail: cliente?['email'],
          clienteTelefone: cliente?['telefone'],
        );
        debugPrint('✅ Participação em campanha registrada');

        // Enviar números da sorte via WhatsApp e Email
        if (campanhaResult['temCampanha'] == true) {
          final numeros = List<String>.from(campanhaResult['numeros'] ?? []);
          final campanhas = List<Map<String, dynamic>>.from(
            campanhaResult['campanhas'] ?? [],
          );

          if (numeros.isNotEmpty) {
            try {
              await NotificacaoService.enviarNotificacoes(
                clienteNome: cliente?['nome'] ?? 'Cliente',
                telefone: cliente?['telefone'],
                email: cliente?['email'],
                numeros: numeros,
                campanhas: campanhas,
              );
              debugPrint('✅ Notificações enviadas');
            } catch (e) {
              debugPrint('⚠️ Erro ao enviar notificações (type=${e.runtimeType})');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao registrar participação (type=${e.runtimeType})');
      }

      // Atualizar status do pedido
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('pre_pedidos')
          .doc(widget.prePedidoId)
          .update({
        'status': 'confirmado',
        'dataConfirmacao': FieldValue.serverTimestamp(),
        'dataAtualizacao': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido confirmado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );

      // Recarregar pedido
      _carregarPedido();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao confirmar pedido: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processando = false);
      }
    }
  }
  */

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _normalizarPedidoParaTela(
    Map<String, dynamic> pedido,
  ) {
    final pedidoId =
        (pedido['pedidoId'] ?? pedido['id'] ?? widget.prePedidoId).toString();
    final codigoRastreio = _resolverCodigoRastreio(pedido);
    final freteNome = _resolverFreteNome(pedido);

    return {
      'pedidoId': pedidoId,
      'status': (pedido['status'] ?? 'pendente').toString(),
      'dataCriacao': pedido['dataCriacao'],
      'dataAtualizacao': pedido['dataAtualizacao'],
      'total': (pedido['total'] as num?)?.toDouble() ?? 0.0,
      'itensResumo': _extrairItensResumo(pedido),
      if (codigoRastreio != null) 'codigoRastreio': codigoRastreio,
      if (freteNome != null) 'freteNome': freteNome,
    };
  }

  List<Map<String, dynamic>> _extrairItensResumo(Map<String, dynamic> pedido) {
    final itensResumo = (pedido['itensResumo'] as List?) ?? const [];
    if (itensResumo.isNotEmpty) {
      return itensResumo
          .map(_asMap)
          .where((item) => item.isNotEmpty)
          .map((item) => {
                'nome': (item['nome'] ?? '').toString(),
                'quantidade': (item['quantidade'] as num?)?.toInt() ?? 1,
              })
          .where((item) => (item['nome'] ?? '').toString().trim().isNotEmpty)
          .toList(growable: false);
    }

    final itensLegados = (pedido['itens'] as List?) ?? const [];
    return itensLegados
        .map(_asMap)
        .where((item) => item.isNotEmpty)
        .map((item) => {
              'nome': (item['nome'] ?? '').toString(),
              'quantidade': (item['quantidade'] as num?)?.toInt() ?? 1,
            })
        .where((item) => (item['nome'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);
  }

  String? _resolverCodigoRastreio(Map<String, dynamic> pedido) {
    final codigo = (pedido['codigoRastreio'] ??
            pedido['codigo_rastreio'] ??
            pedido['rastreio'] ??
            '')
        .toString()
        .trim();
    return codigo.isEmpty ? null : codigo;
  }

  String? _resolverFreteNome(Map<String, dynamic> pedido) {
    final freteNome = (pedido['freteNome'] ?? '').toString().trim();
    if (freteNome.isNotEmpty) return freteNome;

    final frete = pedido['frete'];
    if (frete is Map) {
      final nomeLegado = (frete['nome'] ?? '').toString().trim();
      if (nomeLegado.isNotEmpty) return nomeLegado;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Detalhes do Pedido'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _buildErro()
              : _buildConteudo(),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              _erro!,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _carregando = true;
                  _erro = null;
                });
                _carregarPedido();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    if (_prePedido == null) return const SizedBox();

    final status = (_prePedido!['status'] ?? 'pendente').toString();
    final itens = ((_prePedido!['itensResumo'] as List?) ?? const [])
        .map((item) => _asMap(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final total = (_prePedido!['total'] as num?)?.toDouble() ?? 0.0;
    final dataCriacao = _prePedido!['dataCriacao'];
    final freteNome = (_prePedido!['freteNome'] ?? '').toString().trim();
    final codigoRastreio = (_prePedido!['codigoRastreio'] ?? '').toString().trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header com status
          _buildStatusCard(status, dataCriacao),
          const SizedBox(height: 16),

          // ID do Pedido
          _buildPedidoIdCard(),
          const SizedBox(height: 16),

          // Itens
          _buildSection(
            titulo: 'Itens do Pedido',
            icone: Icons.shopping_bag,
            child: Column(
              children: [
                if (itens.isEmpty)
                  Text(
                    'Resumo dos itens indisponível',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                  )
                else
                  ...itens.map(_buildItemCard),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Resumo Financeiro
          _buildSection(
            titulo: 'Resumo',
            icone: Icons.receipt_long,
            child: Column(
              children: [
                if (freteNome.isNotEmpty) ...[
                  _buildInfoLinha(
                    Icons.local_shipping,
                    'Entrega',
                    freteNome,
                  ),
                  const Divider(height: 16),
                ],
                const Divider(height: 16, thickness: 2),
                _buildResumoLinha('Total', total, destaque: true),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (codigoRastreio.isNotEmpty) ...[
            _buildSection(
              titulo: 'Rastreamento',
              icone: Icons.local_shipping,
              child: _buildInfoLinha(
                Icons.confirmation_number,
                'Código de rastreio',
                codigoRastreio,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mensagem de status do pedido
          const SizedBox(height: 16),
          Card(
            color: status == 'pendente'
                ? Colors.orange[50]
                : status == 'confirmado'
                    ? Colors.green[50]
                    : Colors.red[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    status == 'pendente'
                        ? Icons.schedule
                        : status == 'confirmado'
                            ? Icons.check_circle
                            : Icons.cancel,
                    color: status == 'pendente'
                        ? Colors.orange
                        : status == 'confirmado'
                            ? Colors.green
                            : Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status == 'pendente'
                              ? 'Pedido Aguardando Confirmação'
                              : status == 'confirmado'
                                  ? 'Pedido Confirmado!'
                                  : 'Pedido Cancelado',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: status == 'pendente'
                                ? Colors.orange[900]
                                : status == 'confirmado'
                                    ? Colors.green[900]
                                    : Colors.red[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status == 'pendente'
                              ? 'A loja entrará em contato em breve para confirmar seu pedido.'
                              : status == 'confirmado'
                                  ? 'Seu pedido foi confirmado e está sendo preparado!'
                                  : 'Este pedido foi cancelado.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_usandoFallbackLegado) ...[
            const SizedBox(height: 12),
            Text(
              'Visualização pública em modo de compatibilidade temporária.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],

          // Rodapé
          const SizedBox(height: 24),
          Center(
            child: Text(
              'MasterPalm',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String status, dynamic dataCriacao) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_corStatus(status), _corStatus(status).withValues(alpha:0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _corStatus(status).withValues(alpha:0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            _iconeStatus(status),
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _labelStatus(status),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pedido realizado em',
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.9),
              fontSize: 12,
            ),
          ),
          Text(
            _formatarData(dataCriacao),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPedidoIdCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.tag,
              color: Colors.blue[700],
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ID do Pedido',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.prePedidoId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _copiarPedidoId,
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copiar ID',
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String titulo,
    required IconData icone,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icone, size: 20, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final nome = item['nome'] ?? '';
    final quantidade = item['quantidade'] ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shopping_bag, color: Colors.grey),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${quantidade}x item(ns)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoLinha(String label, double valor, {bool destaque = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: destaque ? 16 : 14,
            fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
            color: destaque ? Colors.black : Colors.grey[700],
          ),
        ),
        Text(
          'R\$ ${_formatarValor(valor)}',
          style: TextStyle(
            fontSize: destaque ? 18 : 14,
            fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
            color: destaque ? Colors.green[700] : Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoLinha(IconData icone, String label, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

