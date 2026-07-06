// lib/screens/order_review_screen.dart

// 🔁 Import condicional: usa dart:io em mobile, e um stub no Web
import 'dart:io' as io
    if (dart.library.html) 'package:master_palm/utils/io_stub.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

// 👇 ajuda a diagnosticar acesso precoce ao Firebase
import '../debug/bootstrap_diagnostics.dart' show FirebaseGuard;

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../core/order_review_sale_intent.dart';
import '../repositories/pedido_repository.dart';
import '../services/loja_id_service.dart';
import '../services/pedido_collection_resolver.dart';
import '../services/temp_order_service.dart';
import '../models/produto.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/vendas_service.dart';
import '../services/sale_intent_service.dart';

class OrderReviewScreen extends StatefulWidget {
  final String orderId;
  final String? lojaId; // opcional (?loja= no link)

  const OrderReviewScreen({
    super.key,
    required this.orderId,
    this.lojaId,
  });

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  final PedidoRepository _pedidoRepository = PedidoRepository();
  Map<String, dynamic>? _order;
  Box<Produto>? _produtos;
  Box<Cliente>? _clientes;
  Box<Venda>? _vendas;
  Box? _config;
  bool _loading = true;
  bool _finalizando = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      FirebaseGuard.require('OrderReviewScreen._load');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('OrderReviewScreen: FirebaseGuard (contexto ok) (type=${e.runtimeType})');
      }
    }

    Map<String, dynamic>? o;

    // 1) Carrega pedido primeiro (para resolver lojaId)
    try {
      o = await TempOrderService.get(widget.orderId);
    } catch (e) {
      debugPrint('OrderReviewScreen: TempOrderService.get falhou (type=${e.runtimeType})');
    }

    if (o == null && (widget.lojaId?.isNotEmpty ?? false)) {
      try {
        o = await _pedidoRepository.getTempPedidoById(
          pedidoId: widget.orderId,
          lojaId: widget.lojaId,
        );
      } catch (e) {
        debugPrint('OrderReviewScreen: Firestore pedidos_temp falhou (type=${e.runtimeType})');
      }
    }

    // 2) Resolve lojaId para usar boxes corretas (multi-loja)
    String? lojaId = widget.lojaId?.trim().isNotEmpty == true
        ? widget.lojaId!.trim()
        : (o?['lojaId']?.toString().trim());
    if (lojaId == null || lojaId.isEmpty) {
      try {
        lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 8));
      } catch (_) {}
    }

    // 2b) Não abrir boxes sem lojaId – evita mistura de dados em multi-tenant
    if (lojaId == null || lojaId.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('OrderReviewScreen: lojaId não resolvido – não abrindo boxes (evita dados errados)');
      }
      if (!mounted) return;
      setState(() {
        _order = o;
        _loading = false;
      });
      return;
    }

    // 3) Abre boxes com HiveBoxNames (produtos_lojaId)
    try {
      await Hive.openBox('config');
      _config = Hive.box('config');

      final prodName = HiveBoxNames.produtos(lojaId);
      final clientName = HiveBoxNames.clientes(lojaId);
      final vendasName = HiveBoxNames.vendas(lojaId);

      if (!Hive.isBoxOpen(prodName)) await Hive.openBox<Produto>(prodName);
      if (!Hive.isBoxOpen(clientName)) await Hive.openBox<Cliente>(clientName);
      if (!Hive.isBoxOpen(vendasName)) await Hive.openBox<Venda>(vendasName);

      _produtos = Hive.box<Produto>(prodName);
      _clientes = Hive.box<Cliente>(clientName);
      _vendas = Hive.box<Venda>(vendasName);
    } catch (e) {
      debugPrint('OrderReviewScreen: erro ao abrir boxes Hive (type=${e.runtimeType})');
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _order = o;
      _loading = false;
    });
  }

  // ---------------- Helpers numéricos e imagens ----------------

  static bool _isHttpImage(String? v) =>
      v != null &&
      v.isNotEmpty &&
      (v.startsWith('http://') || v.startsWith('https://'));

  static double _numAsDouble(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  static int _numAsInt(dynamic v) =>
      (v is num) ? v.toInt() : int.tryParse('$v') ?? 1;

  double _subtotal() {
    final items = (_order?['items'] as List?) ?? const [];
    return items.fold<double>(0.0, (s, it) {
      final preco = _numAsDouble(it['preco'] ?? it['price'] ?? 0);
      final qtd = _numAsInt(it['qtd'] ?? it['qty'] ?? 1);
      return s + (preco * qtd);
    });
  }

  double _freteValor() => _numAsDouble(_order?['frete']?['valor']);
  String _freteNome() => (_order?['frete']?['nome']?.toString() ?? 'Entrega');

  // ---------------- WhatsApp ----------------

  Future<void> _abrirWhatsAppResumo({
    required String receiver,
    required String mensagem,
  }) async {
    final onlyDigits = receiver.replaceAll(RegExp(r'[^0-9]'), '');
    final uriApp = Uri.parse(
        'whatsapp://send?phone=$onlyDigits&text=${Uri.encodeComponent(mensagem)}');
    final uriWeb = Uri.parse(
        'https://wa.me/$onlyDigits?text=${Uri.encodeComponent(mensagem)}');

    if (await canLaunchUrl(uriApp)) {
      await launchUrl(uriApp, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(uriWeb)) {
      await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------- Checagem de estoque (bloqueio) ----------------

  /// Retorna itens sem estoque suficiente.
  /// Cada item: {nome, tamanho, solicitado, disponivel}
  List<Map<String, dynamic>> _itensComEstoqueInsuficiente() {
    if (_order == null || _produtos == null) return const [];
    final items =
        List<Map<String, dynamic>>.from(_order!['items'] as List? ?? []);
    final insuficientes = <Map<String, dynamic>>[];

    for (final it in items) {
      final nome = (it['nome'] ?? it['product'] ?? '').toString();
      if (nome.isEmpty) continue;

      final qtd = _numAsInt(it['qtd'] ?? it['qty'] ?? 1);
      final tam = (it['tamanho']?.toString() ?? '').trim().toLowerCase();

      final prod = _produtos!.values.firstWhere(
        (p) => p.nome.trim().toLowerCase() == nome.trim().toLowerCase(),
        orElse: () => Produto(
          nome: '',
          precoUnitario: 0,
          precoFinal: 0,
          precoSugerido: 0,
          custoReal: 0,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          quantidade: 0,
          categoria: '',
          dataEntrada: DateTime.now(),
        ),
      );

      final disponivel = prod.quantidade; // se não existir, será 0
      if (disponivel < qtd) {
        insuficientes.add({
          'nome': prod.nome.isNotEmpty ? prod.nome : nome,
          'tamanho': tam,
          'solicitado': qtd,
          'disponivel': disponivel,
        });
      }
    }
    return insuficientes;
  }

  bool get _temEstoqueInsuficiente => _itensComEstoqueInsuficiente().isNotEmpty;

  void _mostrarDialogEstoqueInsuficiente() {
    final faltas = _itensComEstoqueInsuficiente();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Estoque insuficiente',
            style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Não é possível finalizar a venda. Ajuste o pedido ou reponha o estoque.'),
            const SizedBox(height: 12),
            ...faltas.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '- ${f['nome']}${(f['tamanho'] as String).isEmpty ? '' : ' (tam. ${f['tamanho']})'}: '
                    'solicitado ${f['solicitado']}, disponível ${f['disponivel']}',
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Ok')),
        ],
      ),
    );
  }

  // ---------------- Finalização ----------------

  Future<void> _finalizar() async {
    if (_order == null || _produtos == null || _clientes == null || _vendas == null || _config == null) return;
    if (_finalizando) return;

    // ❌ Bloqueia finalização se faltar estoque
    if (_temEstoqueInsuficiente) {
      _mostrarDialogEstoqueInsuficiente();
      return;
    }

    setState(() => _finalizando = true);
    try {
    final items =
        List<Map<String, dynamic>>.from((_order!['items'] as List?) ?? []);
    final pagamento = _order!['pagamento']?.toString() ?? 'Dinheiro';
    final clienteMap =
        Map<String, dynamic>.from(_order!['cliente'] as Map? ?? {});
    final clienteNome = clienteMap['nome']?.toString() ?? 'Cliente (Link)';
    final endereco = clienteMap['endereco']?.toString() ?? '';
    final telefone = clienteMap['telefone']?.toString() ?? '';
    final freteNome = _freteNome();
    final freteVal = _freteValor();

    // Monta itens respeitando cadastro local quando existir
    final vendaItens = <VendaItem>[];
    for (final it in items) {
      final nome = (it['nome'] ?? it['product'] ?? '').toString();
      if (nome.isEmpty) continue;

      final qtd = _numAsInt(it['qtd'] ?? it['qty'] ?? 1);
      final preco = _numAsDouble(it['preco'] ?? it['price'] ?? 0);
      final tam = (it['tamanho']?.toString() ?? '');

      final prod = _produtos!.values.firstWhere(
        (p) => p.nome.trim().toLowerCase() == nome.trim().toLowerCase(),
        orElse: () => Produto(
          nome: '',
          precoUnitario: 0,
          precoFinal: 0,
          precoSugerido: 0,
          custoReal: 0,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          quantidade: 0,
          categoria: '',
          dataEntrada: DateTime.now(),
        ),
      );

      vendaItens.add(VendaItem(
        produtoNome: prod.nome.isNotEmpty ? prod.nome : nome,
        quantidade: qtd,
        precoUnitario: prod.precoFinal > 0
            ? prod.precoFinal
            : (prod.precoUnitario > 0 ? prod.precoUnitario : preco),
        tamanho: tam,
        productId: prod.idFirebase.trim().isNotEmpty ? prod.idFirebase : null,
      ));
    }

    // Forma de pagamento única (vinda do link)
    final total = _subtotal() + freteVal;
    double dinheiro = 0, pix = 0, cartao = 0;
    switch (pagamento.toLowerCase()) {
      case 'pix':
        pix = total;
        break;
      case 'cartão':
      case 'cartao':
        cartao = total;
        break;
      default:
        dinheiro = total;
    }

    // Salva venda completa (estoque, histórico, totais, etc.)
    try {
      String? lojaId = widget.lojaId;
      if (lojaId == null || lojaId.trim().isEmpty) {
        lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
      }
      if (lojaId == null || lojaId.trim().isEmpty) {
        throw Exception('Não foi possível identificar a loja. Tente novamente.');
      }
      await VendasService.registrarVendaMulti(
        produtosBox: _produtos!,
        clientesBox: _clientes!,
        vendasBox: _vendas!,
        clienteNome: clienteNome,
        itens: vendaItens,
        dinheiro: dinheiro,
        pix: pix,
        cartao: cartao,
        vendedor: 'Link do Pedido',
        observacao:
            'Entrega: $freteNome (R\$ ${freteVal.toStringAsFixed(2)}) | End.: $endereco | Tel.: $telefone',
        frete: freteVal,
        descontoPct: 0,
        lojaId: lojaId,
        saleIntentId: OrderReviewSaleIntent.saleIntentIdForOrder(widget.orderId),
        saleIntentOrigin: SaleIntentOrigins.orderReview,
      );
    } catch (e) {
      debugPrint('OrderReviewScreen: erro ao registrar venda (type=${e.runtimeType})');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao finalizar venda. Tente novamente. ($e)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Opcional: registra em lojas/{lojaId}/pedidos (histórico por loja; root /pedidos exige admin)
    if (widget.lojaId != null && widget.lojaId!.trim().isNotEmpty) {
      try {
        FirebaseGuard.require('OrderReviewScreen._finalizar->pedidos');
        await _pedidoRepository.createPedido(
          flowType: PedidoFlowType.pedidos,
          lojaId: widget.lojaId,
          data: {
          ..._order!,
          'status': 'concluido',
          'finalizadoEm': FieldValue.serverTimestamp(),
          'lojaId': widget.lojaId,
          },
        );
      } catch (e, st) {
        logE(
          'OrderReviewScreen: falha ao registrar pedido em Firestore (opcional)',
          tag: 'ORDER-REVIEW',
          error: e,
          st: st,
        );
      }
    }

    // Remove do temporário (onde estiver)
    try {
      await TempOrderService.remove(widget.orderId);
    } catch (e1) {
      try {
        FirebaseGuard.require('OrderReviewScreen._finalizar->deleteTemp');
        await _pedidoRepository.deleteTempPedidoEverywhere(
          pedidoId: widget.orderId,
          lojaId: widget.lojaId,
        );
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('OrderReviewScreen: falha ao remover temp (finalizar): remove=${e1.runtimeType}, everywhere=${e2.runtimeType}');
        }
      }
    }

    // Abre WhatsApp com resumo (se configurado)
    final receiver =
        (_config!.get('whatsapp_phone') ?? _config!.get('whatsapp') ?? '')
            .toString();
    if (receiver.isNotEmpty) {
      final resumo = StringBuffer()
        ..writeln('🧾 *Novo pedido concluído*')
        ..writeln('Cliente: $clienteNome')
        ..writeln('Telefone: $telefone')
        ..writeln('Endereço: $endereco')
        ..writeln('Itens:');
      for (final it in vendaItens) {
        final partes = <String>[];
        if (it.tamanho.isNotEmpty) partes.add('Tam: ${it.tamanho}');
        if (it.cor.isNotEmpty) partes.add('Cor: ${it.cor}');
        if (it.variacaoExtraResumo.isNotEmpty) {
          partes.add(it.variacaoExtraResumo);
        }
        final variacoes =
            partes.isNotEmpty ? ' (${partes.join(', ')})' : '';
        resumo.writeln('? ${it.quantidade}x ${it.produtoNome}$variacoes - '
            'R\$ ${it.precoUnitario.toStringAsFixed(2)}');
      }
      resumo
        ..writeln('Frete: $freteNome – R\$ ${freteVal.toStringAsFixed(2)}')
        ..writeln('*Total:* R\$ ${total.toStringAsFixed(2)}')
        ..writeln('Pagamento: $pagamento');

      await _abrirWhatsAppResumo(
          receiver: receiver, mensagem: resumo.toString());
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Venda finalizada e estoque atualizado!')),
    );
    Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _finalizando = false);
    }
  }

  Future<void> _cancelar() async {
    try {
      await TempOrderService.remove(widget.orderId);
    } catch (e1) {
      try {
        FirebaseGuard.require('OrderReviewScreen._cancelar->deleteTemp');
        await _pedidoRepository.deleteTempPedidoEverywhere(
          pedidoId: widget.orderId,
          lojaId: widget.lojaId,
        );
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('OrderReviewScreen: falha ao remover temp (cancelar): remove=${e1.runtimeType}, everywhere=${e2.runtimeType}');
        }
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Pedido cancelado.')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_produtos == null || _clientes == null || _vendas == null || _config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Revisar Pedido')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Dados locais não carregados. Feche e abra o app ou tente novamente.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (_order == null) {
      return const Scaffold(
          body: Center(child: Text('Pedido não encontrado.')));
    }

    final items =
        List<Map<String, dynamic>>.from((_order!['items'] as List?) ?? []);
    final cliente = Map<String, dynamic>.from(_order!['cliente'] as Map? ?? {});
    final total = _subtotal() + _freteValor();
    final temFalta = _temEstoqueInsuficiente;

    return Scaffold(
      appBar: AppBar(title: const Text('Revisar Pedido')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (temFalta)
            Card(
              color: const Color(0xFFFFEBEE), // vermelho claro
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ Estoque insuficiente',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._itensComEstoqueInsuficiente().map((f) => Text(
                          '- ${f['nome']}${(f['tamanho'] as String).isEmpty ? '' : ' (tam. ${f['tamanho']})'}: '
                          'solicitado ${f['solicitado']}, disponível ${f['disponivel']}',
                          style: const TextStyle(color: Colors.red),
                        )),
                  ],
                ),
              ),
            ),
          const Text('Itens', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...items.map((it) {
            final img = it['img']?.toString();
            final nome = (it['nome'] ?? it['product'] ?? '').toString();
            final qtd = _numAsInt(it['qtd'] ?? it['qty'] ?? 1);
            final preco = _numAsDouble(it['preco'] ?? it['price'] ?? 0);
            final tamanho = (it['tamanho']?.toString() ?? '');

            Widget leading;
            if (img == null || img.isEmpty) {
              leading = const Icon(Icons.image);
            } else if (_isHttpImage(img)) {
              leading =
                  Image.network(img, width: 56, height: 56, fit: BoxFit.cover);
            } else if (kIsWeb && img.startsWith('blob:')) {
              // blob: URLs podem estar revogados; não usar Image.network
              leading = const Icon(Icons.image);
            } else if (!kIsWeb) {
              // ✅ usa io.File apenas no mobile
              leading = Image.file(io.File(img),
                  width: 56, height: 56, fit: BoxFit.cover);
            } else {
              leading = Image.network(img,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                return const Icon(Icons.image);
              });
            }

            return ListTile(
              leading: leading,
              title: Text(nome),
              subtitle: Text(
                '${tamanho.isEmpty ? '' : 'Tam.: $tamanho • '}R\$ ${preco.toStringAsFixed(2)}',
              ),
              trailing: Text('x$qtd'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            );
          }),
          const Divider(),
          Text(
              'Frete: ${_freteNome()} – R\$ ${_freteValor().toStringAsFixed(2)}'),
          Text('Total: R\$ ${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('Nome: ${cliente['nome'] ?? ''}'),
          Text('Telefone: ${cliente['telefone'] ?? ''}'),
          Text('Endereço: ${cliente['endereco'] ?? ''}'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelar,
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (temFalta || _finalizando) ? null : _finalizar,
                  child: _finalizando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Finalizar venda'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
