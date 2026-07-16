// M3.8 S2-R6 — Catálogo Interno comercial (vendedores → Nova Venda).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/catalogo_interno_cart.dart';
import '../core/hive_box_names.dart';
import '../core/access_scope_service.dart';
import '../core/produto_cadastro_gate.dart';
import '../design_system/mp_tokens.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../services/permissao_service.dart';
import '../services/store_resolver_facade.dart';
import '../utils/image_helper.dart';
import 'nova_venda_modal.dart';

class CatalogoInternoScreen extends StatefulWidget {
  const CatalogoInternoScreen({super.key});

  @override
  State<CatalogoInternoScreen> createState() => _CatalogoInternoScreenState();
}

class _CatalogoInternoScreenState extends State<CatalogoInternoScreen> {
  Box<Produto>? _produtosBox;
  Box<Cliente>? _clientesBox;
  Box<Venda>? _vendasBox;
  String? _lojaId;
  String _vendedor = 'vendedor';
  AccessScopeIdentity? _scope;

  bool _loading = true;
  bool _semPermissao = false;
  String _busca = '';
  String? _categoriaFiltro;
  bool _somenteFavoritos = false;
  final Set<String> _favoritos = {};

  List<CatalogoInternoCartItem> _carrinho = [];

  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final ok = await PermissaoService.possuiPermissao('vendas');
    if (!ok) {
      if (mounted) {
        setState(() {
          _semPermissao = true;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você não tem permissão para acessar esta tela'),
          ),
        );
      }
      return;
    }

    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    final sessao = await Hive.openBox('sessao');
    final vendedor = (sessao.get('usuario_logado') ??
            sessao.get('usuario_logado_email') ??
            'vendedor')
        .toString();

    if (lojaId == null || lojaId.trim().isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível identificar a loja.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final produtos =
        await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    final clientes =
        await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
    final vendas = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));

    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('catalogo_interno_fav_$lojaId') ?? [];
    final scope = await AccessScopeService.loadIdentity();

    if (!mounted) return;
    setState(() {
      _lojaId = lojaId;
      _vendedor = vendedor;
      _produtosBox = produtos;
      _clientesBox = clientes;
      _vendasBox = vendas;
      _scope = scope;
      _favoritos
        ..clear()
        ..addAll(favs);
      _loading = false;
    });
  }

  Future<void> _persistFavoritos() async {
    final lid = _lojaId;
    if (lid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'catalogo_interno_fav_$lid',
      _favoritos.toList(),
    );
  }

  String _produtoKey(Produto p) {
    final fb = p.idFirebase.trim();
    if (fb.isNotEmpty) return fb;
    return p.key?.toString() ?? p.nome;
  }

  List<Produto> get _produtosVisiveis {
    final box = _produtosBox;
    if (box == null) return const [];
    final isSeller = _scope?.isSeller == true;
    var list = box.values.where((p) {
      if (!isSeller) return true;
      return produtoEstoqueDisponivelParaVendedor(p);
    }).toList();

    final q = _busca.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((p) {
            final sku = (p.codigoBarras.isNotEmpty ? p.codigoBarras : p.sku)
                .toLowerCase();
            return p.nome.toLowerCase().contains(q) ||
                p.categoria.toLowerCase().contains(q) ||
                p.subcategoria.toLowerCase().contains(q) ||
                sku.contains(q);
          })
          .toList();
    }
    if (_categoriaFiltro != null && _categoriaFiltro!.isNotEmpty) {
      list = list
          .where((p) => p.categoriasAssociadas.contains(_categoriaFiltro))
          .toList();
    }
    if (_somenteFavoritos) {
      list = list.where((p) => _favoritos.contains(_produtoKey(p))).toList();
    }
    list.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return list;
  }

  List<String> get _categorias {
    final s = <String>{};
    for (final p in _produtosVisiveis) {
      s.addAll(p.categoriasAssociadas.where((c) => c.trim().isNotEmpty));
    }
    final out = s.toList()..sort();
    return out;
  }

  void _toggleFavorito(Produto p) {
    final k = _produtoKey(p);
    setState(() {
      if (_favoritos.contains(k)) {
        _favoritos.remove(k);
      } else {
        _favoritos.add(k);
      }
    });
    unawaited(_persistFavoritos());
  }

  void _addProduto(Produto p) {
    final img = p.imagens.isNotEmpty ? p.imagens.first : '';
    final item = CatalogoInternoCartItem(
      productId: _produtoKey(p),
      nome: p.nome,
      preco: p.precoComPromocao,
      quantidade: 1,
      tamanho: p.tamanhos.length == 1 ? p.tamanhos.first : '',
      cor: p.cores.length == 1 ? p.cores.first : '',
      imagemUrl: img,
    );
    setState(() {
      _carrinho = CatalogoInternoCartLogic.addOrMerge(_carrinho, item);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${p.nome} adicionado'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _abrirCheckoutNovaVenda() async {
    if (_carrinho.isEmpty) return;
    final produtosBox = _produtosBox;
    final clientesBox = _clientesBox;
    final vendasBox = _vendasBox;
    final lojaId = _lojaId;
    if (produtosBox == null ||
        clientesBox == null ||
        vendasBox == null ||
        lojaId == null) {
      return;
    }

    final itens = CatalogoInternoCartLogic.toNovaVendaItens(_carrinho);
    final obs = CatalogoInternoCartLogic.joinObservacoes(_carrinho);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NovaVendaModal(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        vendedor: _vendedor,
        lojaId: lojaId,
        itensIniciais: itens,
        observacaoInicial: obs.isEmpty ? null : obs,
        onVendaFinalizada: () {},
        onErroAoFinalizar: (msg) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.red.shade700,
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    if (result == true) {
      setState(() => _carrinho = []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venda registrada com sucesso!'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _abrirCarrinhoSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void sync(VoidCallback fn) {
              setState(fn);
              setModal(() {});
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.35,
              maxChildSize: 0.92,
              builder: (_, scroll) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Carrinho interno',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _carrinho.isEmpty
                                  ? null
                                  : () {
                                      sync(() => _carrinho = []);
                                    },
                              child: const Text('Limpar'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _carrinho.isEmpty
                            ? const Center(child: Text('Carrinho vazio'))
                            : ListView.builder(
                                controller: scroll,
                                itemCount: _carrinho.length,
                                itemBuilder: (_, i) {
                                  final item = _carrinho[i];
                                  return ListTile(
                                    title: Text(item.nome),
                                    subtitle: Text(
                                      [
                                        _money.format(item.preco),
                                        if (item.tamanho.isNotEmpty)
                                          'Tam: ${item.tamanho}',
                                        if (item.cor.isNotEmpty)
                                          'Cor: ${item.cor}',
                                      ].join(' · '),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                              Icons.remove_circle_outline),
                                          onPressed: () {
                                            sync(() {
                                              _carrinho =
                                                  CatalogoInternoCartLogic
                                                      .setQuantity(
                                                _carrinho,
                                                item.lineKey,
                                                item.quantidade - 1,
                                              );
                                            });
                                          },
                                        ),
                                        Text('${item.quantidade}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.add_circle_outline),
                                          onPressed: () {
                                            sync(() {
                                              _carrinho =
                                                  CatalogoInternoCartLogic
                                                      .setQuantity(
                                                _carrinho,
                                                item.lineKey,
                                                item.quantidade + 1,
                                              );
                                            });
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.red),
                                          onPressed: () {
                                            sync(() {
                                              _carrinho =
                                                  CatalogoInternoCartLogic
                                                      .remove(
                                                _carrinho,
                                                item.lineKey,
                                              );
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Text('Subtotal',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  Text(
                                    _money.format(
                                        CatalogoInternoCartLogic.subtotal(
                                            _carrinho)),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed: _carrinho.isEmpty
                                      ? null
                                      : () {
                                          Navigator.pop(ctx);
                                          unawaited(_abrirCheckoutNovaVenda());
                                        },
                                  icon: const Icon(Icons.point_of_sale),
                                  label: const Text('Ir para Nova Venda'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: MpColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_semPermissao) {
      return Scaffold(
        appBar: AppBar(title: const Text('Catálogo interno')),
        body: const Center(
          child: Text('Sem permissão para vender neste catálogo.'),
        ),
      );
    }

    final produtos = _produtosVisiveis;
    final subtotal = CatalogoInternoCartLogic.subtotal(_carrinho);
    final qtdItens =
        _carrinho.fold<int>(0, (a, e) => a + e.quantidade);

    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: const Text('Catálogo interno'),
        actions: [
          IconButton(
            tooltip: _somenteFavoritos ? 'Todos' : 'Favoritos',
            onPressed: () =>
                setState(() => _somenteFavoritos = !_somenteFavoritos),
            icon: Icon(
              _somenteFavoritos ? Icons.favorite : Icons.favorite_border,
              color: _somenteFavoritos ? Colors.red : null,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _busca = v),
              decoration: InputDecoration(
                hintText: 'Pesquisar produtos…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_categorias.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Todas'),
                      selected: _categoriaFiltro == null,
                      onSelected: (_) =>
                          setState(() => _categoriaFiltro = null),
                    ),
                  ),
                  ..._categorias.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(c),
                        selected: _categoriaFiltro == c,
                        onSelected: (_) => setState(() {
                          _categoriaFiltro =
                              _categoriaFiltro == c ? null : c;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: produtos.isEmpty
                ? const Center(child: Text('Nenhum produto encontrado'))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                    itemCount: produtos.length,
                    itemBuilder: (_, i) {
                      final p = produtos[i];
                      final key = _produtoKey(p);
                      final fav = _favoritos.contains(key);
                      final thumb =
                          p.imagens.isNotEmpty ? p.imagens.first : '';
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _addProduto(p),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(16)),
                                      child: thumb.isEmpty
                                          ? Container(
                                              color: Colors.grey[200],
                                              child: const Icon(
                                                Icons.image_outlined,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                            )
                                          : buildPlatformImage(thumb,
                                              fit: BoxFit.cover),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: IconButton(
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              Colors.white.withOpacity(0.9),
                                        ),
                                        icon: Icon(
                                          fav
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: fav ? Colors.red : Colors.grey,
                                          size: 20,
                                        ),
                                        onPressed: () => _toggleFavorito(p),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                                child: Text(
                                  p.nome,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 0, 10, 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _money.format(p.precoComPromocao),
                                        style: const TextStyle(
                                          color: MpColors.success,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.add_shopping_cart,
                                      size: 18,
                                      color: MpColors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _carrinho.isEmpty
          ? null
          : Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(28),
              color: MpColors.success,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _abrirCarrinhoSheet,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        'Carrinho ($qtdItens) · ${_money.format(subtotal)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

